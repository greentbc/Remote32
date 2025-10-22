//
//  encoder.swift
//  
//
//  Created by Tyler Stiffler on 9/30/25.
//

///TODO: Add defer/error things for rmt_new_ir_nec_encoder



extension rmt_symbol_word_t {
    // Read-only views of the fields
    var duration0: UInt16 { UInt16(val & 0x7FFF) }                     // bits 0..14
    var level0: Bool      { ((val >> 15) & 0x1) != 0 }                 // bit 15
    var duration1: UInt16 { UInt16((val >> 16) & 0x7FFF) }             // bits 16..30
    var level1: Bool      { ((val >> 31) & 0x1) != 0 }                 // bit 31
}


let IR_RESOLUTION_HZ = UInt32(    1000000) // 1MHz resolution, 1 tick = 1us
let IR_RX_GPIO_NUM = gpio_num_t(  19)
let IR_TX_GPIO_NUM = gpio_num_t(  18)
let IR_NEC_DECODE_MARGIN = UInt32(200)

let NEC_LEADING_CODE_DURATION_0 = UInt32( 9000)
let NEC_LEADING_CODE_DURATION_1 = UInt32( 4500)
let NEC_PAYLOAD_ZERO_DURATION_0 = UInt32( 560)
let NEC_PAYLOAD_ZERO_DURATION_1 = UInt32( 560)
let NEC_PAYLOAD_ONE_DURATION_0  = UInt32( 560)
let NEC_PAYLOAD_ONE_DURATION_1  = UInt32( 1690)
let NEC_REPEAT_CODE_DURATION_0  = UInt32( 9000)
let NEC_REPEAT_CODE_DURATION_1  = UInt32( 2250)

var s_nec_code_address = UInt16()
var s_nec_code_command = UInt16()
var s_temp_reading = UInt16()



func hex(_ x: UInt16) -> String {
    if x < 4095 {
        return "0\(String(x, radix: 16, uppercase: true))"
    }
    else {
        return String(x, radix: 16, uppercase: true)
    }
    //String(format: "%04X", x) is not reasonably available in embedded swift atm

}

struct rmt_ir_nec_encoder_t {
 
    var base: rmt_encoder_t           // the base "class", declares the standard encoder interface
    var copy_encoder: UnsafeMutablePointer<rmt_encoder_t>?  // use the copy_encoder to encode the leading and ending pulse
    var bytes_encoder: UnsafeMutablePointer<rmt_encoder_t>?// use the bytes_encoder to encode the address and command data
    var nec_leading_symbol: rmt_symbol_word_t // NEC leading code with RMT representation
    var nec_ending_symbol: rmt_symbol_word_t  // NEC ending code with RMT representation
    var state: rmt_encode_state_t
}

struct ir_nec_scan_code_t {
    var address: UInt16
    var command: UInt16
}

struct ir_nec_encoder_config_t {
    var resolution: UInt32
}



func logInfo(_ tag: String, _ message: String) {
    //tag.withCString { cTag in
    //message.withCString { cMsg in
    // Logs printable characters, split into lines of up to 16 chars
    let n = UInt16(message.utf8.count)
    esp_log_buffer_char_internal(tag, message, n, ESP_LOG_INFO)
    // }
    //}
}


func symbolWordToBits(
    level0: Bool,
    duration0: UInt16,
    level1: Bool,
    duration1: UInt16
) -> UInt32 {
    
    var val : UInt32 = (level1 ? 1 : 0) << 31
    // return val
    //var duration1: UInt16 { UInt16((val >> 16) & 0x7FFF) }
    val =  (UInt32(duration1) << 16) | (val)
    val =  (UInt32(level0 ? 1 : 0) << 15) | (val)
    val =  (UInt32(duration0) << 0) | (val)
    
    
    return val
}




func rmt_new_ir_nec_encoder(
    _ config: UnsafePointer<ir_nec_encoder_config_t>?,
    _ retEncoder: UnsafeMutablePointer<rmt_encoder_handle_t>?
) -> esp_err_t {
    var ret = ESP_OK
   
    
    guard let config = config, var retEncoder = retEncoder else {
        logInfo("Encoder", "invalid argument")
        return ESP_ERR_INVALID_ARG
    }
    
    
    
    guard let nec_encoder_raw = rmt_alloc_encoder_mem(Int(MemoryLayout<rmt_ir_nec_encoder_t>.stride)) else {
        logInfo("Encoder", "no mem for ir nec encoder")
        return ESP_ERR_NO_MEM
    }
    let nec_encoder = UnsafeMutableRawPointer(nec_encoder_raw).bindMemory(to: rmt_ir_nec_encoder_t.self, capacity: 1)
    
    

    nec_encoder.pointee.base.encode = rmt_encode_ir_nec
    nec_encoder.pointee.base.del = rmt_del_ir_nec_encoder
    nec_encoder.pointee.base.reset = rmt_ir_nec_encoder_reset
//
    var copy_encoder_config = rmt_copy_encoder_config_t()

    let newCopyEncoderErr = rmt_new_copy_encoder(&copy_encoder_config, &nec_encoder.pointee.copy_encoder)
    if newCopyEncoderErr != ESP_OK {
        logInfo("Encoder", "create copy encoder failed")
        return newCopyEncoderErr
    }



    //use initialize(to:) if leading symbol isn't init when nec_encoder is
    nec_encoder.pointee.nec_leading_symbol = rmt_symbol_word_t(
        val: symbolWordToBits(
            level0: true,
            duration0: 9000 * UInt16(config.pointee.resolution / 1000000),
            level1: false,
            duration1: 4500 * UInt16(config.pointee.resolution / 1000000)
        )
    )
//

    nec_encoder.pointee.nec_ending_symbol = rmt_symbol_word_t(
        val: symbolWordToBits(
            level0: true,
            duration0: 560 * UInt16(config.pointee.resolution / 1000000),
            level1: false,
            duration1: 0x7FFF
            )
        )
        
    var bytes_encoder_config = rmt_bytes_encoder_config_t(
        bit0: rmt_symbol_word_t(val:symbolWordToBits(
            level0: true,
            duration0: 560 * UInt16(config.pointee.resolution / 1000000),
            level1: false,
            duration1: 560 * UInt16(config.pointee.resolution / 1000000)
        )
        ),
        bit1: rmt_symbol_word_t(val:symbolWordToBits(
            level0: true,
            duration0: 560 * UInt16(config.pointee.resolution / 1000000),
            level1: false,
            duration1: 1690 * UInt16(config.pointee.resolution / 1000000)
        )
        ),
        flags: rmt_bytes_encoder_config_t.__Unnamed_struct_flags(msb_first: 0)
    )
    

    let newBytesEncoderErr = rmt_new_bytes_encoder(&bytes_encoder_config, &nec_encoder.pointee.bytes_encoder)
    if newBytesEncoderErr != ESP_OK {
        logInfo("Encoder", "create bytes encoder failed")
        return newBytesEncoderErr
    }
    
    retEncoder.pointee = UnsafeMutablePointer(&nec_encoder.pointee.base)//Likely problem with this
    logInfo("impro", "Where retEncoder is questionable")
    return ESP_OK
//err:
//    if (nec_encoder) {
//        if (nec_encoder->bytes_encoder) {
//            rmt_del_encoder(nec_encoder->bytes_encoder);
//        }
//        if (nec_encoder->copy_encoder) {
//            rmt_del_encoder(nec_encoder->copy_encoder);
//        }
//        free(nec_encoder);
//    }
 //   return ret
}



func rmt_encode_ir_nec(
    _ encoder: UnsafeMutablePointer<rmt_encoder_t>?,
    _ channel: rmt_channel_handle_t?,
    _ primary_data: UnsafeRawPointer?,
    _ data_size: size_t,
    _ ret_state: UnsafeMutablePointer<rmt_encode_state_t>?
) -> size_t

{

    guard let encoder = encoder else { fatalError("rmt encode fail") }
    let baseOffset = MemoryLayout<rmt_ir_nec_encoder_t>.offset(of: \.base)!
    let nec_encoder = UnsafeMutableRawPointer(encoder)
        .advanced(by: -baseOffset)
        .assumingMemoryBound(to: rmt_ir_nec_encoder_t.self)
    
    
    
    var session_state: rmt_encode_state_t = RMT_ENCODING_RESET
    var state: rmt_encode_state_t = RMT_ENCODING_RESET
    var encoded_symbols = size_t(0)
    var  scan_code = primary_data!.assumingMemoryBound(to: ir_nec_scan_code_t.self)
    //guard var  scan_code = primary_data else { fatalError("rmt encode fail")}
    guard var copy_encoder = nec_encoder.pointee.copy_encoder else { fatalError("rmt encode fail")}
    guard var bytes_encoder = nec_encoder.pointee.bytes_encoder else { fatalError("rmt encode fail")}
    
    

    switch (nec_encoder.pointee.state) {
    case RMT_ENCODING_RESET: // send leading code
        encoded_symbols += copy_encoder.pointee.encode(copy_encoder, channel, &nec_encoder.pointee.nec_leading_symbol, Int(MemoryLayout<rmt_symbol_word_t>.stride), &session_state)
        if ((session_state.rawValue & RMT_ENCODING_COMPLETE.rawValue) != 0) {
            nec_encoder.pointee.state = RMT_ENCODING_COMPLETE
        }
        if ((session_state.rawValue & RMT_ENCODING_MEM_FULL.rawValue) != 0) {
            state.rawValue |= RMT_ENCODING_MEM_FULL.rawValue
            ret_state!.pointee = state
            return encoded_symbols
            

        }
        fallthrough

    case RMT_ENCODING_COMPLETE: // send address UInt32(MemoryLayout<uint16_t>.stride)
        var address = scan_code.pointee.address
        encoded_symbols += bytes_encoder.pointee.encode(bytes_encoder, channel, &address, Int(MemoryLayout<UInt16>.stride), &session_state)
        if ((session_state.rawValue & RMT_ENCODING_COMPLETE.rawValue) != 0) {
            nec_encoder.pointee.state = RMT_ENCODING_MEM_FULL
        }
        if ((session_state.rawValue & RMT_ENCODING_MEM_FULL.rawValue) != 0 ) {
            state.rawValue |= RMT_ENCODING_MEM_FULL.rawValue

            ret_state!.pointee = state
            return encoded_symbols
        }
        fallthrough
    case RMT_ENCODING_MEM_FULL: // send command
        var command = scan_code.pointee.command
        encoded_symbols += bytes_encoder.pointee.encode(bytes_encoder, channel, &command, Int(MemoryLayout<UInt16>.stride), &session_state)
        if ((session_state.rawValue & RMT_ENCODING_COMPLETE.rawValue) != 0 ) {
            nec_encoder.pointee.state.rawValue = 3
        }
        if ((session_state.rawValue & RMT_ENCODING_MEM_FULL.rawValue) != 0 ) {
            state.rawValue |= RMT_ENCODING_MEM_FULL.rawValue
            ret_state!.pointee = state
            return encoded_symbols
        }
        fallthrough
    case rmt_encode_state_t(3): // send ending code
        encoded_symbols += copy_encoder.pointee.encode(copy_encoder, channel, &nec_encoder.pointee.nec_ending_symbol, Int(MemoryLayout<rmt_symbol_word_t>.stride), &session_state)
        if ((session_state.rawValue & RMT_ENCODING_COMPLETE.rawValue) != 0 ) {
            nec_encoder.pointee.state.rawValue = RMT_ENCODING_RESET.rawValue
            state.rawValue |= RMT_ENCODING_COMPLETE.rawValue
        }
        if ((session_state.rawValue & RMT_ENCODING_MEM_FULL.rawValue) != 0 ) {
                state.rawValue |= RMT_ENCODING_MEM_FULL.rawValue
            ret_state!.pointee = state
            return encoded_symbols
        }
    default:
        fatalError("unknown state \(nec_encoder.pointee.state)")
        break
    }
    ret_state!.pointee = state
    return encoded_symbols
}


func rmt_del_ir_nec_encoder(_ encoder: UnsafeMutablePointer<rmt_encoder_t>?) -> esp_err_t
{
    
    guard let encoder = encoder else { return ESP_FAIL }
    
    let baseOffset = MemoryLayout<rmt_ir_nec_encoder_t>.offset(of: \.base)!
    let nec_encoder = UnsafeMutableRawPointer(encoder)
        .advanced(by: -baseOffset)
        .assumingMemoryBound(to: rmt_ir_nec_encoder_t.self)
    
    if let copy = nec_encoder.pointee.copy_encoder {
        rmt_del_encoder(copy)
        nec_encoder.pointee.copy_encoder = nil
    }
    if let bytes = nec_encoder.pointee.bytes_encoder {
        rmt_del_encoder(bytes)
        nec_encoder.pointee.bytes_encoder = nil
    }
    
    free(nec_encoder)
    
    return ESP_OK
}


func rmt_ir_nec_encoder_reset(_ encoder: UnsafeMutablePointer<rmt_encoder_t>?) -> esp_err_t
{
    guard let encoder = encoder else { return ESP_FAIL }
    
    let baseOffset = MemoryLayout<rmt_ir_nec_encoder_t>.offset(of: \.base)!
    let nec_encoder = UnsafeMutableRawPointer(encoder)
        .advanced(by: -baseOffset)
        .assumingMemoryBound(to: rmt_ir_nec_encoder_t.self)
    
    if let copy = nec_encoder.pointee.copy_encoder {
        rmt_encoder_reset(copy)
        nec_encoder.pointee.copy_encoder = nil
    }
    if let bytes = nec_encoder.pointee.bytes_encoder {
        rmt_encoder_reset(bytes)
        nec_encoder.pointee.bytes_encoder = nil
    }
    
    nec_encoder.pointee.state = RMT_ENCODING_RESET
    
    
    return ESP_OK
}



public func nec_check_in_range(_ signal_duration: UInt16, _ spec_duration: UInt32) -> Bool {
    return (signal_duration < (spec_duration + IR_NEC_DECODE_MARGIN)) &&
    (signal_duration > (spec_duration - IR_NEC_DECODE_MARGIN))
}
public func  nec_parse_logic0(_ rmt_nec_symbols: UnsafePointer<rmt_symbol_word_t>) -> Bool {
    return nec_check_in_range(rmt_nec_symbols.pointee.duration0, NEC_PAYLOAD_ZERO_DURATION_0) &&
    nec_check_in_range(rmt_nec_symbols.pointee.duration1, NEC_PAYLOAD_ZERO_DURATION_1)
}
public func nec_parse_logic1(_ rmt_nec_symbols: UnsafePointer<rmt_symbol_word_t>) -> Bool {
    return nec_check_in_range(rmt_nec_symbols.pointee.duration0, NEC_PAYLOAD_ONE_DURATION_0) &&
    nec_check_in_range(rmt_nec_symbols.pointee.duration1, NEC_PAYLOAD_ONE_DURATION_1)
}



public func  nec_parse_logic0_not(_ rmt_nec_symbols: UnsafePointer<rmt_symbol_word_t>) -> Bool {
    return nec_check_in_range(rmt_nec_symbols.pointee.duration0, NEC_PAYLOAD_ZERO_DURATION_1) &&
    nec_check_in_range(rmt_nec_symbols.pointee.duration1, NEC_PAYLOAD_ZERO_DURATION_0)
}
public func nec_parse_logic1_not(_ rmt_nec_symbols: UnsafePointer<rmt_symbol_word_t>) -> Bool {
    return nec_check_in_range(rmt_nec_symbols.pointee.duration0, NEC_PAYLOAD_ONE_DURATION_1) &&
    nec_check_in_range(rmt_nec_symbols.pointee.duration1, NEC_PAYLOAD_ONE_DURATION_0)
}

public func nec_parse_frame(_ rmt_nec_symbols: UnsafePointer<rmt_symbol_word_t>) -> Bool {
    
    let cur = UnsafeBufferPointer<rmt_symbol_word_t>(start:rmt_nec_symbols, count: 64)
    var curIndex = Int(0)
    
    var address:UInt16 = 0
    var command:UInt16 = 0

    
    let valid_leading_code = nec_check_in_range(cur[curIndex].duration0, NEC_LEADING_CODE_DURATION_0) &&
    nec_check_in_range(cur[curIndex].duration1, NEC_LEADING_CODE_DURATION_1)
    if (!valid_leading_code) {
        //print("invalid leading code or out of range")
        return false
    }
    curIndex += 1

    for i in 0..<16 {
        if (nec_parse_logic1(cur.baseAddress!.advanced(by: curIndex))) {
            address |= 1 << i
        } else if (nec_parse_logic0(cur.baseAddress!.advanced(by: curIndex))) {
            address &= ~(1 << i)
        } else {
            //print("adr not 0 or 1")
            return false
        }
        curIndex += 1
    }

    for i in 0..<16 {
        if (nec_parse_logic1(cur.baseAddress!.advanced(by: curIndex))) {
            command |= 1 << i
        } else if (nec_parse_logic0(cur.baseAddress!.advanced(by: curIndex))) {
            command &= ~(1 << i)
        } else {
            //print("cmd 0 or 1")
            return false
            
        }
        curIndex += 1
    }
    // save address and command
    s_nec_code_address = address
    s_nec_code_command = command
   
    return true
}


func nec_parse_frame_repeat(_ rmt_nec_symbols: UnsafePointer<rmt_symbol_word_t>) -> Bool {
    return nec_check_in_range(rmt_nec_symbols.pointee.duration0, NEC_REPEAT_CODE_DURATION_0) &&
    nec_check_in_range(rmt_nec_symbols.pointee.duration1, NEC_REPEAT_CODE_DURATION_1)
}

func parse_nec_frame(_ rmt_nec_symbols: UnsafePointer<rmt_symbol_word_t>, _ symbol_num: size_t) -> ir_nec_scan_code_t? {


    let cur = UnsafeBufferPointer<rmt_symbol_word_t>(start:rmt_nec_symbols, count: symbol_num)
//  print("Frame start---")
//   Print out each received symbol for debug
//    for word in cur {
//        print("{\(word.level0):\(word.duration0)},{\(word.level1):\( word.duration1)}")
//    }
//  print("---Frame end: \(symbol_num) symbols")
    
    // decode RMT symbols
    switch (symbol_num) {
    case 34: // NEC normal frame
        if (nec_parse_frame(rmt_nec_symbols)) {
            //print("Address=\(hex(s_nec_code_address)), Command=\(hex(s_nec_code_command))\r\n")
            return ir_nec_scan_code_t(address: s_nec_code_address, command: s_nec_code_command)
        }
//        else{
//            print("Not NEC logic")
//        }
        break
    case 2: // NEC repeat frame
        if (nec_parse_frame_repeat(rmt_nec_symbols)) {
            //print("Address=\(hex(s_nec_code_address)), Command=\(hex(s_nec_code_command)), repeat\r\n")
            return ir_nec_scan_code_t(address: s_nec_code_address, command: s_nec_code_command)
        }
        break
    default:
        print("Unknown frame\r\n")
        break
    }
    return nil
}

func rmt_rx_done_callback(_ channel: rmt_channel_handle_t?, edata: UnsafePointer<rmt_rx_done_event_data_t>?, user_data: UnsafeMutableRawPointer?) -> Bool {
   
    
    
    var high_task_wakeup:BaseType_t = pdFALSE
    let receive_queue = QueueHandle_t(user_data)
    xQueueGenericSendFromISR(receive_queue, edata, &high_task_wakeup, queueSEND_TO_BACK)

    return high_task_wakeup == pdTRUE
}

public func pdMS_TO_TICKS(_ ms: UInt32) -> TickType_t {
    return TickType_t((UInt32(ms) * UInt32(configTICK_RATE_HZ)) / 1000)
}
