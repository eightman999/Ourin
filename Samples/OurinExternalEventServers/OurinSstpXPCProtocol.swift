// OurinSstpXPCProtocol.swift
import Foundation

@objc public protocol OurinSstpXPCProtocol {
    func deliverSSTP(_ request: Data, with reply: @escaping (Data) -> Void)
}
