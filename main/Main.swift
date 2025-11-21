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

/*
 Uses ESP___:
 rmt_rx_channel_config_t
 rmt_new_rx_channel()
 rmt_new_tx_channel()
 rmt_alloc_encoder_mem()
 
 
 Uses FreeROTS:
 xQueueGenericCreate()
 
 */



//Set mode for rx disable?
//I will need addresses and CMDs for HDMI,AC,Projector

//Should change encoder to not have nec_parse_frame and parse_nec_frame



@_cdecl("app_main")
func main() {

    //Setup

    let rxEnable = false//TODO exists before  True
    
    
    var rx_channel: rmt_channel_handle_t? = nil
    var tx_channel: rmt_channel_handle_t? = nil
    var receive_config = rmt_receive_config_t(
        signal_range_min_ns: 1250,
        signal_range_max_ns: 12000000
    )
    
    
    var cbs = rmt_rx_event_callbacks_t(on_recv_done: rmt_rx_done_callback)
    
    
    let receive_queue = xQueueGenericCreate(
        UInt32(1),
        UInt32(MemoryLayout<rmt_rx_done_event_data_t>.stride),
        queueQUEUE_TYPE_BASE)
    
    var rx_channel_cfg = rmt_rx_channel_config_t(
        gpio_num: IR_RX_GPIO_NUM,
        clk_src: RMT_CLK_SRC_DEFAULT,
        resolution_hz: IR_RESOLUTION_HZ,
        mem_block_symbols: 64,
        flags: rmt_rx_channel_config_t.__Unnamed_struct_flags(),
        intr_priority: 0)

    
    guard rmt_new_rx_channel(&rx_channel_cfg, &rx_channel) == ESP_OK else {
        fatalError("fail new rx ch")
    }
    
    
    var tx_channel_cfg = rmt_tx_channel_config_t(
        gpio_num: IR_TX_GPIO_NUM,
        clk_src: RMT_CLK_SRC_DEFAULT,
        resolution_hz: IR_RESOLUTION_HZ,
        mem_block_symbols: 64,
        trans_queue_depth: 4,
        intr_priority: 0,
        flags: rmt_tx_channel_config_t.__Unnamed_struct_flags(),
    )
    
    var carrier_cfg = rmt_carrier_config_t(
        frequency_hz: 38000, // 38KHz
        duty_cycle: 0.33,
        flags: rmt_carrier_config_t.__Unnamed_struct_flags()
    )
    var nec_encoder_cfg = ir_nec_encoder_config_t(
        resolution: IR_RESOLUTION_HZ
    )
    
    
    
    guard rmt_new_tx_channel(&tx_channel_cfg, &tx_channel) == ESP_OK else {
        fatalError("RMTNewTX issues")
    }
    
    
    guard (rmt_rx_register_event_callbacks(rx_channel, &cbs, UnsafeMutableRawPointer(receive_queue)) == ESP_OK) else {
        fatalError("register_cbs failed")
    }
    
    
    guard rmt_apply_carrier(tx_channel, &carrier_cfg) == ESP_OK else {
        fatalError("TX carrier issues")
    }
    var transmit_config = rmt_transmit_config_t(
            loop_count: 0,
            flags: rmt_transmit_config_t.__Unnamed_struct_flags()
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
    
    let remote = IRRemote(transmit_config: transmit_config, tx_channel: tx_channel, encoder: nec_encoder)
    var txMarkTime = esp_timer_get_time()
    var hdmiTog = false
    
    
    logInfo("my_app","main loop")
    while (true) {
            // wait for RX done signal
        if (xQueueReceive(receive_queue, &rx_data, pdMS_TO_TICKS(1000)) == pdPASS) {
            
            if rxEnable {
                // parse the receive symbols and print the result if valid
                if let nec = parse_nec_frame(rx_data.received_symbols, rx_data.num_symbols) {
                    guard let receivedAddress = deviceAddress.init(rawValue: nec.address) else {
                        logInfo("Remote", "Unknown address")
                        print("Address=\(hex(nec.address)), Command=\(hex(nec.command))\r\n")
                        continue//TODO: Test this to make sur it has the correct level of continue. Should start receive again. But I think it will continue the while(true) loop
                    }
                    
                    //Check that it is known address
                    switch receivedAddress {
                    case deviceAddress.HDMI:
                        logInfo("Remote", "HDMI Switcher")
                        break
                    case deviceAddress.AC:
                        logInfo("Remote", "AC Unit")
                        break
                    default:
                        logInfo("Remote", "Unknown address")
                        
                    }
                }
                
            }
            // start receive again
            guard rmt_receive(rx_channel, raw_symbols, ((MemoryLayout<rmt_symbol_word_t>.stride)*64), &receive_config) == ESP_OK
            else {fatalError("start receive failed")}
        }
        else {//else for nothing in the queue
            if (txMarkTime + 6400000 < esp_timer_get_time()){
                txMarkTime = esp_timer_get_time()
                
                var codeProjectorPS5 = ir_nec_scan_code_t(
                    address: deviceAddress.HDMI.rawValue,
                    command: videoCMD.ProjectorPS5.rawValue
                )
                //my HDMI switxher needs the code sent twice
                //remote.transmit(scan_code: &codeProjectorPS5, doubleSend: true)
                if hdmiTog {remote.switchHDMI(videoCMD.A3)}
                else {remote.switchHDMI(videoCMD.A4)}
                hdmiTog.toggle()
                logInfo("ReMo", "Sent")
            }
        }
    }
    
}
