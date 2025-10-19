//===----------------------------------------------------------------------===//
//
//
//
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//
//
//
//===----------------------------------------------------------------------===//





@_cdecl("app_main")
func main() {
  print("🏎️   Hello, Embedded Swift!")
    

    
    logInfo("my_app", "mk RMT RX ch")
    var rx_channel_cfg = rmt_rx_channel_config_t(
        gpio_num: IR_RX_GPIO_NUM,
        clk_src: RMT_CLK_SRC_DEFAULT,
        resolution_hz: IR_RESOLUTION_HZ,
        mem_block_symbols: 64,
        flags: rmt_rx_channel_config_t.__Unnamed_struct_flags(),
        intr_priority: 0,
        )

    var rx_channel: rmt_channel_handle_t? = nil
    guard rmt_new_rx_channel(&rx_channel_cfg, &rx_channel) == ESP_OK else {
        fatalError("fail new rx ch")
    }
    
    let itemSize = UInt32(MemoryLayout<rmt_rx_done_event_data_t>.stride)
    

    let receive_queue: QueueHandle_t? = xQueueGenericCreate(UInt32(1), itemSize, queueQUEUE_TYPE_BASE)// UInt8(0))
    guard let receive_queue = receive_queue else {
        fatalError("xQueueGenericCreate returned nil")
    }
    

    var cbs = rmt_rx_event_callbacks_t(on_recv_done: rmt_rx_done_callback)
    guard (rmt_rx_register_event_callbacks(rx_channel, &cbs, UnsafeMutableRawPointer(receive_queue)) == ESP_OK) else {
        fatalError("register_cbs failed")
    }
    
        // the following timing requirement is based on NEC protocol
        var receive_config = rmt_receive_config_t(
            signal_range_min_ns: 1250,
            signal_range_max_ns: 12000000
        )

        
    var tx_channel_cfg = rmt_tx_channel_config_t(
            gpio_num: IR_TX_GPIO_NUM,
            clk_src: RMT_CLK_SRC_DEFAULT,
            resolution_hz: IR_RESOLUTION_HZ,
            mem_block_symbols: 64,
            trans_queue_depth: 4,
            intr_priority: 0,
            flags: rmt_tx_channel_config_t.__Unnamed_struct_flags(),
        )
    var tx_channel: rmt_channel_handle_t? = nil
    guard rmt_new_tx_channel(&tx_channel_cfg, &tx_channel) == ESP_OK else {
        fatalError("RMTNewTX issues")
    }
        
    var carrier_cfg = rmt_carrier_config_t(
            frequency_hz: 38000, // 38KHz
            duty_cycle: 0.33,
            flags: rmt_carrier_config_t.__Unnamed_struct_flags()
        )
    
    guard rmt_apply_carrier(tx_channel, &carrier_cfg) == ESP_OK else {
        fatalError("TX carrier issues")
    }
    var transmit_config = rmt_transmit_config_t(
            loop_count: 0, // no loop
            flags: rmt_transmit_config_t.__Unnamed_struct_flags()
        )

    var nec_encoder_cfg = ir_nec_encoder_config_t(
             resolution: IR_RESOLUTION_HZ
        )
    var nec_encoder: rmt_encoder_handle_t? = nil
    guard rmt_new_ir_nec_encoder(&nec_encoder_cfg, UnsafeMutableRawPointer(&nec_encoder)
        .assumingMemoryBound(to: rmt_encoder_handle_t.self)) == ESP_OK else {
        fatalError("new encoder issues")
    }

    
    
    guard rmt_enable(tx_channel) == ESP_OK else {
        fatalError("rmt_enable tx")
    }

    guard rmt_enable(rx_channel) == ESP_OK else {
        fatalError("rmt_enable rx")
    }
    

    let raw_symbols = UnsafeMutablePointer<rmt_symbol_word_t>.allocate(capacity: 64)
    
    
    var  rx_data = rmt_rx_done_event_data_t()
    
    guard rmt_receive(rx_channel, raw_symbols, ((MemoryLayout<rmt_symbol_word_t>.stride)*64), &receive_config) == ESP_OK else {
        fatalError("rmt_receive failed")
    }
    
    
    logInfo("my_app","main loop")
    
        while (true) {
//            // wait for RX done signal
            if (xQueueReceive(receive_queue, &rx_data, pdMS_TO_TICKS(1000)) == pdPASS) {
//                // parse the receive symbols and print the result
                parse_nec_frame(rx_data.received_symbols, rx_data.num_symbols);
//                // start receive again
                guard rmt_receive(rx_channel, raw_symbols, ((MemoryLayout<rmt_symbol_word_t>.stride)*64), &receive_config) == ESP_OK
                else {
                    fatalError("rmt_receive failed")
                }
            } else {
                var scan_code = ir_nec_scan_code_t(
                    address: 0xF508,
                    command: 0xF10E
                )
                guard rmt_transmit(tx_channel, nec_encoder, &scan_code, MemoryLayout<ir_nec_scan_code_t>.stride, &transmit_config) == ESP_OK else {
                    fatalError("rmt_transmit failed")
                }
                
            }
        }
//    }
    
    
    
    
}
