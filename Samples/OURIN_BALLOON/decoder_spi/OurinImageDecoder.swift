
public protocol OurinImageDecoder { static var name:String { get } static func probe(data:Data, utiHint:String?) -> Bool; static func decode(data:Data) throws -> (Int,Int,Data) }
