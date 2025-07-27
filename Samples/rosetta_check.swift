// samples/rosetta_check.swift
import Foundation

public func isRunningUnderRosetta() -> Bool {
    var flag: Int32 = 0
    var size = MemoryLayout<Int32>.size
    let rc = sysctlbyname("sysctl.proc_translated", &flag, &size, nil, 0)
    return rc == 0 && flag == 1
}

print("Rosetta:", isRunningUnderRosetta())
