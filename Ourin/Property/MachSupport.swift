//
//  MachSupport.swift
//  Ourin
//
//  Created by eightman on 2025/07/27.
//

let HOST_VM_INFO64_COUNT: mach_msg_type_number_t =
    UInt32(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
