//
//  Remote.swift
//  
//
//  Created by Tyler Stiffler on 11/1/25.
// Class to contain my IR remote uses and to keep it separate from the encoder


//goal to test and get projector IR working. First to test:
//Think address is: 02FD
//Epson power code: A05F


let IR_RESOLUTION_HZ = UInt32(    1000000) // 1MHz resolution, 1 tick = 1us
let IR_RX_GPIO_NUM = gpio_num_t(  3)
let IR_TX_GPIO_NUM = gpio_num_t(  2)
let IR_NEC_DECODE_MARGIN = UInt16(200)
//Todo: check the tolerances to see what range works
let NEC_LEADING_CODE_DURATION_0 = UInt16( 9800)//HDMI switcher remote seems to do 9800, not 9000 like NEC
let NEC_LEADING_CODE_DURATION_1 = UInt16( 4500)
let NEC_PAYLOAD_ZERO_DURATION_0 = UInt16( 560)
let NEC_PAYLOAD_ZERO_DURATION_1 = UInt16( 560)
let NEC_PAYLOAD_ONE_DURATION_0  = UInt16( 560)
let NEC_PAYLOAD_ONE_DURATION_1  = UInt16( 1690)
let NEC_REPEAT_CODE_DURATION_0  = UInt16( 9000)
let NEC_REPEAT_CODE_DURATION_1  = UInt16( 2250)
let NEC_PAYLOAD_END_DURATION_0  = UInt16( 560)

var s_nec_code_address = UInt16()
var s_nec_code_command = UInt16()
var s_temp_reading = UInt16()






class IRRemote {
    var transmit_config: rmt_transmit_config_t
    var tx_channel: rmt_channel_handle_t?
    var encoder: rmt_encoder_handle_t?
    
    init( transmit_config: rmt_transmit_config_t,
          tx_channel: rmt_channel_handle_t?,
          encoder: rmt_encoder_handle_t?) {
        self.transmit_config = transmit_config
        
        guard let tx_channel = tx_channel else { return }
        self.tx_channel = tx_channel
        guard let encoder = encoder else { return }
        self.encoder = encoder
        
    }
    func transmit( scan_code: inout ir_nec_scan_code_t, doubleSend: Bool = false) {
        
        guard rmt_transmit(tx_channel, encoder, &scan_code, MemoryLayout<ir_nec_scan_code_t>.stride, &transmit_config) == ESP_OK else {
            fatalError("rmt_transmit failed")
        }
        if doubleSend {
            guard rmt_transmit(tx_channel, encoder, &scan_code, MemoryLayout<ir_nec_scan_code_t>.stride, &transmit_config) == ESP_OK else {
                fatalError("rmt_transmit failed")
            }
        }
    }
    
    func switchHDMI(_ cmd: videoCMD) {
        var scan_code = ir_nec_scan_code_t(
            address: deviceAddress.HDMI.rawValue,
            command: cmd.rawValue
        )
        
        transmit(scan_code: &scan_code, doubleSend: true)
    }
    
    func isKnownAddress(_ address: UInt16) -> Bool {
        guard let testAddress = deviceAddress(rawValue: address) else { return false }
        return true
        
    }
    
    
}


enum acCMD: UInt16 {
    case t74High,t74H = 0x8C6F
    
}
enum deviceAddress: UInt16  {
    case HDMI = 0x7F80
    case AC = 0xF508
}

public enum videoCMD: UInt16 {
    case on,off = 0xED12
    
    //OutPut A - 27in LCD
    //In 1 - Out A
    case A1, LGPS5 = 0xFE01
    //In 2 - Out A
    case A2, LGATV = 0xFC03
    //In 3 - Out A
    case A3 = 0xFB04
    //In 4 - Out A
    case A4 = 0xF906
    
    //OutPut B - Projector
    //In 1 - Out B
    case B1, ProjectorPS5 = 0xF807
    //In 2 - Out B
    case B2, ProjectorATV = 0xF609
    //In 3 - Out AB
    case B3 = 0xF50A
    //In 4 - Out B
    case B4 = 0xE01F
}


func cmdToTempString(_ cmd: UInt16) -> String {
    switch cmd {
        
        
    case 0x836F:
        return "82+"
        
    case 0x026F:
        return "82-"
        
    case 0xFD6F:
        return "81+"
    case 0x7C6F:
        return "81-"
        
    case 0xBC6F:
        return "81+"
    case 0x3D6F:
        return "80"
    case 0xDC6F:
        return "81-"
        
        
    case 0x5d6f:
        return "79+"//added
    case 0x2EB7:
        return "79-?"
    case 0x4EB7:
        return "78??"
        
    case 0x9D6F:
        return "78+"
    case 0x1C6F:
        return "78-"
        
    case 0xEC6F:
        return "77+"
    case 0x6D6F:
        return "77-"
        
    case 0xAD6F:
        return "76+"
    case 0x2C6F:
        return "76-"
        
        
    case 0xCD6F:
        return "75+"
    case 0x4C6F:
        return "75-"
        
    case 0x8C6F:
        return "74+"
    case 0x0D6F:
        return "74-"
        
        
    case 0xF46F:
        return "73+"
    case 0x756F:
        return "73-"
        
        
    case 0xB56F:
        return "72+"
        
        
        
    default:
        return hex(cmd)
    }
    
}




