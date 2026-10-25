import Foundation

/// KeyAgreement（secp256k1 の ECDH）。結果は共有の点の x 座標（32 バイト）そのままで、ハッシュはしない。
enum InternalCryptoKeyAgreement {
    static var functions: [InternalSaoriFunction] { [keyAgreement] }

    private static var keyAgreement: InternalSaoriFunction {
        InternalSaoriFunction("KeyAgreement", positionals: 3, options: ["key-in", "peer-in", "out"]) { call, _ in
            guard call.positionals[0].lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "") == "secp256k1" else {
                throw InternalSaoriError.unsupportedAlgorithm
            }
            let secret = try InternalSaoriCodec.decode(call.positionals[1], format: call.option("key-in"), defaultFormat: "hex", charset: nil)
            let peer = try InternalSaoriCodec.decode(call.positionals[2], format: call.option("peer-in"), defaultFormat: "hex", charset: nil)
            guard let shared = InternalSecp256k1.sharedSecret(secret: secret, peer: peer) else { throw InternalKeyCodec.invalidKey }
            return InternalSaoriResult(try InternalSaoriCodec.encode(shared, format: call.option("out"), defaultFormat: "hex", charset: nil))
        }
    }
}
