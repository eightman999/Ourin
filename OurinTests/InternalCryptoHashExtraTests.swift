import Foundation
import Testing
@testable import Ourin

private struct HashExtraOutcome {
    var status: Int
    var result: String?
    var error: String?
}

private func extraCall(_ function: String, _ arguments: [String] = [], context: InternalSaoriContext = .none) -> HashExtraOutcome {
    var lines = ["EXECUTE SAORI/1.0", "Charset: UTF-8", "Sender: test", "Module: internal_crypto", "Argument0: \(function)"]
    for (index, value) in arguments.enumerated() { lines.append("Argument\(index + 1): \(value)") }
    let text = InternalSaoriRegistry.shared.handle(requestText: lines.joined(separator: "\r\n") + "\r\n\r\n", context: context)
    let response = try! SaoriProtocol.parseResponse(text)
    return HashExtraOutcome(status: response.statusCode, result: response.headerValue("Result"), error: response.headerValue("ErrorDescription"))
}

private func extraOK(_ outcome: HashExtraOutcome, _ expected: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(outcome.status == 200, "status \(outcome.status) \(outcome.error ?? "")", sourceLocation: sourceLocation)
    #expect(outcome.result == expected, sourceLocation: sourceLocation)
}

private func extraFails(_ outcome: HashExtraOutcome, _ status: Int, _ description: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(outcome.status == status, "got \(outcome.status) \(outcome.error ?? "")", sourceLocation: sourceLocation)
    #expect(outcome.error == description, sourceLocation: sourceLocation)
}

/// 試験データ: i 番目のバイトが (i * 7 + 3) & 0xff。
private func pattern(_ count: Int) -> Data {
    Data((0..<count).map { UInt8(truncatingIfNeeded: $0 * 7 + 3) })
}

private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

private let extraAlgorithms = ["sha512-256", "sha3-224", "sha3-256", "sha3-384", "sha3-512", "blake2b512", "blake2s256"]

// 期待値はすべて Python の hashlib / hmac で計算したもの。
struct InternalCryptoHashExtraTests {

    private static let digests: [String: [Int: String]] = [
        "sha512-256": [
            0: "c672b8d1ef56ed28ab87c3622c5114069bdd3ad7b8f9737498d0c01ecef0967a",
            1: "05b577a248fe933b7c4cdaf4a50e9d61eb8cba9f86c4ad546ac25a0341128ed6",
            55: "8c12c6a555202a2f24eae9d29d5901bf14d8355b08fdd880b962813c30e2e50e",
            56: "d8d15e81e95d2c68bde6c76da58ff17930bcc53926ab3fae45d28c420e4f06cd",
            63: "12bbbb739014d2158f881b0d98fe55399980e2f520dcd46fddbb934d6c4b134c",
            64: "f6fd50d9eff545c7d1810c1a6d31428de85a3584d974a3830775fd65fe2cb929",
            111: "32889a63b00e93a91df09b4292875c8e9ea2d30e482b2f5ab713396275e9378b",
            112: "468a00c6f938065156bfddf56b22592f569052587264673bc893e92cd1953953",
            119: "486b962b750cd088ebf28aec2d5dbda078108d75af0db128e392bfdceaff68e5",
            127: "b7c1bcb3d1d523364187e023ee03210674ee05a8fd54d40aad07ecf6bdfe4c8c",
            128: "5e14bd0208397b56f5f1b3afb8e48bfcce3c7312684a46bbe9b210503680e547",
            129: "6c92b5cdba34ee8137d902ba15d4f6246bb2a07c0fef5a0fa536bc8d8db0390f",
            135: "d060532f2cdf72312a9048fe9b2016342f43b60c10c5836b096375a3d6faab83",
            136: "f5e7b00f51109d50530e22645343ea277480ccf63d1c9a22571e1d4f06e3dc33",
            137: "2df4f0f276d8b1fb4532e2cce580df3b4170d44150a8fd5be2b8e16983a9de9b",
            1000: "14271b3d36ca983ae2da2693d995fe68412c0bd5394ec2f05b763586db6e24fd",
        ],
        "sha3-224": [
            0: "6b4e03423667dbb73b6e15454f0eb1abd4597f9a1b078e3f5b5a6bc7",
            1: "b740a3b446920772a10caf69736eb712d7dab3b380e7c1a2def19b7a",
            55: "35f01d634075939445ee073170ac19eca17ee5d92746afa3aaaf0585",
            56: "676779a38b85088a8b8adbb184039f9267aba25f27c0ff5b1778c371",
            63: "b7267ed5c17885524bce70f0c968a1c3e1a54a85d7d2aa70169219b6",
            64: "3d1c96b68a5312984a03e3614c45086a4dee65ca6f3a6d5a177af1c7",
            111: "7847f6117581e25ab866ef4508f3a51a2da4be20d44016a630e7966e",
            112: "2f1512ce21488309efc9b36499d4ba16231e04d22a471eae07aa2c73",
            119: "66f4d83df1d42a811e99fe3fe50a0182db0fe1d72f5b2c8f0c2de4ec",
            127: "8a1ab38bfb31395b46ec29c62d83badc5f89b588b2457f7e6e39d5da",
            128: "62abbb70fd8ef74c4b94e1e4b8798f0af75edc1908c541f5c09cabec",
            129: "5f278642f050dc815725e4845db32b903c711be52dd7ff278a5168c0",
            135: "1020297b2062e4a80055cb9c8a8ca9645fe854fafa2c4aba3a5ca66b",
            136: "f3ed6ce9b05b8497549ffb0653305e08a1eee9f0b643db6991ffa264",
            137: "2deca7a9f2f78765132defcb91e4c58cc4182c2d9308ba28e4ee38bc",
            1000: "56812d3d31242051de174106777f4108c791ab801f1569f73d57fa0b",
        ],
        "sha3-256": [
            0: "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a",
            1: "e3ed56bd086d8958483a12734fa0ae7f5c8bb160ef9092c67e82ed9b19e4c7b2",
            55: "7b08ced19b17fcd5e225b1a8b489387e122c18d2d31a5f70325310ca210c7cfa",
            56: "e72d9fadd664156719a0861a4b0786cbf80ac2638bd4e6dd0b473876c78a78f7",
            63: "1275539a6596eb01fbc83a54af2f2994aa7ea8beb0b0d440ae07c620ad8eaa9f",
            64: "85c576bd8097a119432293d7b09da76d336aff9acda1c0708cf03bdd999911cd",
            111: "1fc816a1c9bfb6fee349fb661b97d87a1adce7a3ec7a584de1fd9105cbd2d0a1",
            112: "b2826938a19cca0b3f31274fa0d6dd36424508d245a16722a7b443efcfc167af",
            119: "fca1a02979f0e333a4a976d6b2b7d89c2074e8139107f14f875b22d4e368e6cb",
            127: "31578857f28c795c37ceb9bfffd3d24267d338e622927ae128330a5b07f22358",
            128: "fcb6ea7388b68266e5df9f9beaf980fca55fdc6393f4d97ce1bcb2096eb4a975",
            129: "7f516cd0d670dc44936a6f7e9b67271e41d88502acb3936a02b464f9475ca2cc",
            135: "d9dcf1f98e49a79b0643a9e68fef48079ff8777c5e7e7f93469ded65f192ac71",
            136: "743bd32e775ac7387a57d4d574c89ddef5ebcb08bb5cc6b88c55a27b5035cc45",
            137: "01d47e8d6dce6e3dcbf1baa6f845b6ace4ef74bd17da8176ecc49bc35dbe5d21",
            1000: "bd8b4d76041e0135e53fab1aaf425c7b1c129d8878ffb64cc31230ccafd7dc7c",
        ],
        "sha3-384": [
            0: "0c63a75b845e4f7d01107d852e4c2485c51a50aaaa94fc61995e71bbee983a2ac3713831264adb47fb6bd1e058d5f004",
            1: "80fe0aa4889193dd2b9924e34d2170835a0731de3e299e70748c3906f4f0eba35d531e61e4eb318bf8bde6fe3de9436c",
            55: "81fff3492217fc76c2fbaa623250712b2df6af73ea84b84177e1a0b828b2af80eb73bbb321380f00cff46cab86cfe06f",
            56: "1dd96d1e434fdde6b3d38624f16ea3395243113ed4f4ebeafadf1210c88112149dddfb46bf1fa19418cf0ea391522892",
            63: "19e0cf651bee5a9898b41bc7061faf30b19704dfe31dd88b138a4f9625d5341bff91c01267f09009d08c933a6f5ea7bc",
            64: "b9240ffef3debbe9b930f9f67210ffa0fb33f620fc715ab56845d1b212473d9388709ad46d68afbf1b21a6ef252a2732",
            111: "035759380ed782126de8e88dc6f93800aead897e7a0cd6404cb6aa1acec4be0da633b7646db273979cbb3e1bc97f0498",
            112: "67bcc67bde67f0c03fe0a5237dcd6ae7804088bae687bbe76a4171a1030e873a3ea0b1be6573a357814318aa274f4e63",
            119: "981b7363d3df761dd0f0419b2f6f33882d1cf528928f487eac071faf4b423f3a456195e891edb4064fe28f8c518525b3",
            127: "6bd7c6b3de93c9fd07295dfe640e7d0625ecc6def79adbcd22019ca7a6aa84547a8286de2f418fd0e5d1dcf58f055acb",
            128: "50cd60bf83e7440e396fab0904ba49754267d15bf00e5afdc71336b6c9402336be0b15a272119703cbb7ab3da5406001",
            129: "d8a8ac09a99d742c51a1080dd894d67127ee3affb7f8b11e14171ebd87f21604c69bda86e77ebe1eebc7015c93f8d70f",
            135: "4143a14ba7c5973d9e9bc20b7b53bde5cef330c8bfcd795bfc72fde07309175beaf2f390ed1d66312ce47633e4ceb234",
            136: "b78775c23ceb19ee61274146b8e83a7768c7d4e4872417b146e569d1c4507668c148196fb799ae1d97d312f41e140e69",
            137: "623dff354350f43641bb491ad1f159a667bad50d33f65e1e2d7ca9397b84263b5e391e6e194668b39b395116c044cda3",
            1000: "01269eed23d8f1c00d333933989211974c16fed038dfde30f8514168ae13e8409f565dbe4d81399b6ed23db9762f7989",
        ],
        "sha3-512": [
            0: "a69f73cca23a9ac5c8b567dc185a756e97c982164fe25859e0d1dcc1475c80a615b2123af1f5f94c11e3e9402c3ac558f500199d95b6d3e301758586281dcd26",
            1: "a63f9712aadceb0fe16f1881719a802294830fa1f7a0e58ff26a45a814309961c5007f43f4e224a82d3f538a6c8af7d87ec71fb6661bfac0dc0cd9367ddb04ce",
            55: "e0fb9f904a8d3533ed3ae0c035552c204dc0a71656b9279b7cd1ffa9f3d3ce9d3d2435eedf1255174d4e5ffd75bd2793e4cbcdfb970fad0eaae144d90c51d680",
            56: "585ee6b4ae1195ea09e07b15809e69a7fefcd9b8f28bf78b2eefcb4353e6285020777cc12a341af5735af617192553750088d7383af14c229f8487f3ef84e187",
            63: "ef3d22309d3cf4ce62e7f5913e3c8266e92bca25230a0f99db0c2e169c2609f635bd10a26ecc8a640bab84990708cad41520266815a214d4b62c57f9dfd08bd3",
            64: "f37322220063c7eb72c37e9ede7eaa19d20836e3144d7fa26847d2b2234232b942999eadb626ca668d5d9063f353ddc9460186de2e5b0041d9367e6880068ee0",
            111: "16f214637c753c5b461fab872a6548b64662c9654d8e7304c9db6d28c2851a9aeb11ee0d3b3a2c046c78f2bfda4c82e94e4a52849811b598cc7c1f2ab5828103",
            112: "571d1152e406b434c075924711fa94bb42a25dcb907fdd951969ac2e163caea91a84c4fae3f6ab78a4feac15a7a9e6c69b6c1588d508dc11e3b4a0fcc9de155c",
            119: "2b4f50f23354746f38cd8f75becdc1393f81a29c4fb190b6f2a1f7a9d6ee09686b85ed6e7ab45e59bdd189fc2fc715029a34ccac65020b5b3ce80940c965fd7e",
            127: "591a01c19e9a3b4cc2f910dc95cc057b3b82af53bb7d91d775b2bf00024435733a320a3ab82e7251c10cf1461825a32f86c2c8ac00f5c174e78401dc5370f896",
            128: "469992409e1433702f7787fc5bf787db2e3db04af63f06c6c34b647adc4deb92dc96cb5e5a50d97a05b685f76fb0ff4c057fe07ed8542d38a988a922fe600ade",
            129: "a455cead1dac677a33532a8962fb07f985a8d26d176df407cb4b43ce6b5ddd708d6a0ec25237f24261972233aa62afab09d26e70c552fa3ad74440ccf6e02d47",
            135: "9e9d81e346cf9a62dc4bda518e4096db553188368da1535eaa441982b98d399c0c8f0136f987886b94d1770387e07b276660317ccb66884cc7427550b7780cd4",
            136: "62c81b78426786e5a5d431082d98857c7e6b1988fd721478386233be5c19731cea3944dc24e192fb976e422d8bd31524c35026e615ab54c31a58ab772abfe6d7",
            137: "3fd9dc45a7cdc291153d7b714ad68d824184c4166d2c980d41d5eaf9266e03892f965346361f62cb34404cfea6ea165dcdd8c34be99abdc9c500a1fedc315402",
            1000: "3d71681b54b99f11ddeb233b0a41b65896f7b30dda9e83d52864a4e818a09408e2f306028abe973298f96ee081a06e5ac8156cd7b856f0eb28270e1ca37bd0c6",
        ],
        "blake2b512": [
            0: "786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce",
            1: "4fe4da61bcc756071b226843361d74944c72245d23e8245ea678c13fdcd7fe2ae529cf999ad99cc24f7a73416a18ba53e76c0afef83b16a568b12fbfc1a2674d",
            55: "cd3d304c5fc217e84778b997f89dc654a6a44a88b1fd43c4668e4adfbbe2b0d169002a6f98b22ab98dde4603477dcdaeac3e6ff320b1059531fd8b6c36738e67",
            56: "b84c95e7cb1bab5b0f5acfdd426cd90091fe5f98b2f9c047ea71542ffe6e757c29b47ec42c9fdbe423b43083f711fb546f0c3237dd42fe311ff4544d627f295a",
            63: "70b2a0e6daecac22c7a2df82c06e3fc0b4c66bd5ef8098e4ed54e723b393d79ef3bceba079a01a14c6ef2ae2ed1171df1662cd14ef38e6f77b01c7f48144dd09",
            64: "3db7bb5c40745f0c975ac6bb8578f590e2cd2cc1fc6d13533ef725325c9fddff5cca24e7a591a0f6032a24fad0e09f6df873c4ff314628391f78df7f09cb7ed7",
            111: "4a2d61debfb29cecd41c05bfb98b1ec0198a0673118eb2c6eeb9a09c7be6707bda4304e2c617790477dce166e510ef0b834e4fa60479f9ac85df28f9bf36a14d",
            112: "7249a2011abf019553cc93049ed40ea6c09665de6e7a47b18f4aa4341248a57ae3e7d6f1a252a633154e4811ca6c3336b36d8e57cf122d8b7e32b783f70bc1df",
            119: "c3155c76b381d664433787b1e29597168d1d48862d1475ec27146d51582b96a37794422f3c4c2117e3c5f5ea7b4b3669ce59cd1b4ac23e9551deda954b57ec83",
            127: "71546bbf9110ad184cc60f2eb120fcfd9b4dbbca7a7f1270045b8a23a6a4f4330f65c1f030dd2f5fabc6c57617242c37cf427bd90407fac5b9deffd3ae888c39",
            128: "2d9e329f42afa3601d646692b81c13e87fcaff5bf15972e9813d7373cb6d181f9599f4d513d4af4fd6ebd37497aceb29aba5ee23ed764d8510b552bd088814fb",
            129: "47889df9eb4d717afc5019df5c6a83df00a0b8677395e078cd5778ace0f338a618e68b7d9afb065d9e6a01ccd31d109447e7fae771c3ee3e105709194122ba2b",
            135: "c6a955e0596582f752fd76d9946857e2814f6cf708b5d5acb2cbd60cd3521b40c973c1e9324a3fade29c1e6945cdc0d8459de12d71bdad1c338c623df89a6ac3",
            136: "0cc0696654257080227f3db6ccaae4e0b5f910e16fe81d086b15a57c69e47e17e42d6a044fca24998aa3840110b06de1257da9a82aa7e9103c49b63aab32092f",
            137: "6fbd31d644d761b477fe26042edcb949b68aabe2d8abe8ac99bc4dd4121f40a931707b910fb3a187bfcae5ead5c9f3de481405c4f33957bc1830326cb3736037",
            1000: "4bdd2c9cf31d797a81d245c989ffb7515143ca345c66f73087dd5c58bf642bf083ba16894eab79e3b08d5126404d833e7510271b50be36a7b7cbbb46f5c89fac",
        ],
        "blake2s256": [
            0: "69217a3079908094e11121d042354a7c1f55b6482ca1a51e1b250dfd1ed0eef9",
            1: "a28ac19d6bcbe2cd1d7de183485768d598e996b07889b9b11f418cb1b4a4fb0d",
            55: "691697264a9ff7f6f5605335fc509f137845246ce7169d30fbf71574102ffb63",
            56: "5cbb7d8e7b6c8e857af099e6b539e63e1df9185042fb3543ba0d18c1e2834093",
            63: "de27df0e375d83c49f1af9ca8270f9f2fe7b70bf800fc01672db0e9746021ebf",
            64: "5377e4ff957bda4d4535f4879876b71a61056c4cec31e78397c66ec47a86a130",
            111: "7baab2925c12039a34eecf48c4f968b1842eae9adf96c746e83d81fc10734c1b",
            112: "6df7df19e635ab6d56a7fa19f5f4a70d4b51879fb97d265d2de9efad1accb9b6",
            119: "9745104a4c7cde9dfd91d85bb4e0a695db815cc85a9323b78f631eb346b39393",
            127: "6846f99493436241d0a6f289c9a911b1d0f4860db8f2b5df5295ffd37d03a3c4",
            128: "83470c75afa23d90cd7659906e4b47daa278131fbb225241dd37a40fd5355ac7",
            129: "26fd8892ab0a5f12d4acbff1efd7dcd92b99e2d377f888f07e3cb81b232b11cf",
            135: "4efa0dcfd666586f610f59b05e2d5e1b2a336d3743b8ad44b242617a388d428f",
            136: "972fe8ebb1c5a1a1ae14d8bdef125f42f60815dfe2d718e17787222f3c3ebc43",
            137: "03d7ae9bf46ce4a3e885b303da7d84066f2d3973c83e908789ba7d6cd0a8d65d",
            1000: "02a016193469710efadf8fb005ca19b509331cb847df5598cc0794bded669681",
        ],
    ]

    @Test
    func digestMatchesReferenceForVariedLengths() {
        for (algorithm, vectors) in Self.digests {
            for (length, expected) in vectors {
                let outcome = extraCall("Digest", [algorithm, hex(pattern(length)), "--data-in=hex"])
                #expect(outcome.status == 200 && outcome.result == expected, "\(algorithm) \(length): \(outcome.result ?? outcome.error ?? "")")
            }
        }
    }

    @Test
    func knownAnswersForAbc() {
        extraOK(extraCall("Digest", ["sha512-256", "abc"]), "53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23")
        extraOK(extraCall("Digest", ["sha3-224", "abc"]), "e642824c3f8cf24ad09234ee7d3c766fc9a3a5168d0c94ad73b46fdf")
        extraOK(extraCall("Digest", ["sha3-256", "abc"]), "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532")
        extraOK(extraCall("Digest", ["sha3-384", "abc"]), "ec01498288516fc926459f58e2c6ad8df9b473cb0fc08c2596da7cf0e49be4b298d88cea927ac7f539f1edf228376d25")
        extraOK(extraCall("Digest", ["sha3-512", "abc"]), "b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0")
        extraOK(extraCall("Digest", ["blake2b512", "abc"]), "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923")
        extraOK(extraCall("Digest", ["blake2s256", "abc"]), "508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982")
    }

    @Test
    func algorithmNamesAreNormalized() {
        for name in ["SHA3-256", "sha3_256", "Sha3256"] {
            extraOK(extraCall("Digest", [name, "abc"]), "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532")
        }
        extraFails(extraCall("Digest", ["sha3", "abc"]), 400, "unsupported algorithm")
        extraFails(extraCall("Digest", ["blake2", "abc"]), 400, "unsupported algorithm")
    }

    private static let hmacs: [String: [Int: [String]]] = [
        "sha512-256": [
            0: ["f6a69e8f50b53a2ad52875eb41f8a4255e3f9aca453ff7d3357ae18e5464b108", "a48819f9899edab25d4df69ba331be382ff6065d0318ac45d378d0f079894346"],
            1: ["400620a94c302c61e10fcff3db03b1992ae7205d6636c071be0d5680dd426406", "abbd61511c0b38867cd2f88cdee4790c2c8bca9976718c75fd36895dd1441211"],
            63: ["1d3bbd9226ff1c0ed95f07617e6892a9b505601e867320f59ccf955989a4af39", "0610bf3ba5e8787755b23ac6340bbdbdfbd5c12f556d8c87fbf9311bc34f58ad"],
            127: ["a82ee905463b17a822b8a2c137da9fc538841ef6097d93b5aa3f2c5ce0d8b8f3", "28dabb3771ec7df4720062e353cd10095d0788d28f09dc1e006d76c66232fa70"],
            128: ["9caf0b4dda5a8c0e99fd50a2da6fb9add2545a316790b2a4bb8c1f0648a027cf", "9a950c3a400bd0f3c3d7bc4813e59913d8bcf55996b2c1e8ec1cec26f8a96e67"],
            136: ["0deab5fd57f0d3bd3aedb4a1622d590575fab27e0af74ea01af696cba1684b0e", "46403d4c3e424423d7c681509c8e1cd173686276a0647d8b19fe84e69b7c12b3"],
            137: ["b5e34b5e230cbf8f3cb3d16d1f8a1f269b4487b14d922749ce25e6ef65405317", "c6b79ac0faec7079fc759888e2fb64a35264b8dff5a7aef8fbaa6d7dc160843c"],
            1000: ["c01435b65ec1c53e8602dad9ba4ed3041fef94c065ace61cd8fc029fe4e5dac2", "59c7516d6e9339c65947ab8df4bc1df4951e94925d5b528f5d8b5447fafaa1f6"],
        ],
        "sha3-224": [
            0: ["8f481e10aa1ab054f9862d9b2c2ec2be515ec8355e60c452eff83efc", "fccd35f2f50e7cd1e248fc8fb9623990a8a047a39bfcc70b77cfe09e"],
            1: ["c0e64f1a01a68d5c5413a1e83acd99cfca196d14fddb12a620a3e8b6", "5a423396082213c2593e37fe1df63009f9443f4dd84b53b14f7058bd"],
            63: ["566799ab6959327d32389ceaa521b088b82751bac0664531a0cef585", "94cbe3037ca85972f9c7cfca8392f8cd0ac664dd278055299bcd9c2a"],
            127: ["2a89e283e47fe2b922a2e44abd2f6fd56551c16d703ec5afffb9b0ea", "0228c4a0e0e68a088775590e820706e449e5f782ced5f396263a44b0"],
            128: ["d9251741d12231aa53c3b0159a568e03fdd8447f2f7fd184b05ef205", "83cfe2767727ffee296def4d5d6c2274f267463d7243e439c2207202"],
            136: ["bd30640ceb85c8d357e50df60b68fa350b6a3ca51557c32f332571c9", "e0a9a9d67925889644f4084772e1e327759003b27b67cb168bedb1b8"],
            137: ["f1d982604886d68b47e493d9e504c8e6e56c5d6ff61147651d96888c", "3b706e9909d2a5e84c043d979687a346d5bb861e65c5064f72e2a96b"],
            1000: ["944ba59f7612dc2438e1e3e77bcc195503becf7fdb85038aed1075cc", "48b4e0e31e7a5beff62fe08df48cb3852a9c1d42fcab7806e544ca60"],
        ],
        "sha3-256": [
            0: ["74f3c030ecc36a1835d04a333ebb7fce2688c0c78fb0bcf9592213331c884c75", "b8d325a23938e7131e5d0e2a6bf32d7abc490801a797f99b6e962cd869bd3cea"],
            1: ["a1bf9c57e0c091783c6e4c501263beeb4441aa5e296efaae005509eb2f52c702", "f0e7a8ab0dca4e22dd3f6b5081055e8b03512c32fc57c7a2c07125a09e2f8fca"],
            63: ["6a99623c008d8c856040c46ab56d9110b2a230d7a1c9d79555992422297c896f", "11a2fb341dd84e1c9e54eca36774defae1337b8b9b43e54573c3970da2a05867"],
            127: ["4c020921e9c649330d8fae5b4629ac8db1c774772be864ffed23345dd8eb412f", "ebf615d2fbdefa669f1bca7f2d3ad85abbe6f2f06810ca867706c2130aeda18e"],
            128: ["a3a6f717fd0b11ba67829ac8ec27290b4a52545b4ccf637426ddfddef23dd6ac", "129e6d928a9adc82a110948598f17e91ea20fd059bf33eb5d76672066e9156dc"],
            136: ["c0c7f996ffa0d4f20941ec20e34f9eb8fab9b6893ef95064d90f7c605f31f835", "232ab9f1f81d4853742ce6a0db08fe83390ccc26bcadafac08ac70b92fff21ce"],
            137: ["706b905669dd60d12bcaa400f0ebaa1f7a6d36b4a433fdbab7d59f202f98cead", "1bae3a2bd73789c729fce4749690f1a0177ee2ada162641df07cce5512609ad2"],
            1000: ["b97ddc4a913fea038edc29d73aebc866d6b2b26e8ccf1f2b571b6f275249ed83", "cc1981f38d0fd7eb24a0abb49b101329b75e6672080a49c5b855ba141d032dcf"],
        ],
        "sha3-384": [
            0: ["9139ba623c8c521d0a103bcf868041c73fa30a9e89d2a5fca9102a748be86dc15853b6b50cce3a24c008bce88182006d", "556dd765cdcac3690d86b6acfac14d06a90b235579a622cf898691cd7be2304153661c7e8e83ed383f6501e8a8b8a51e"],
            1: ["bf767f9bb5ec7442bbf2345ef56ccaa507cce3c77555772d9271166122963ec69edd2d69ee4e1d7a9718f354007e30da", "78555ff0d7d10ad2b791cb5c5893eec74108af5b2fc322a59aad795e32d6edfdd4bc76562cae7944e5dc144e352b06fb"],
            63: ["c0c734aa3378b1af7b51dd42455b826869903624a355e50956e3ff4997a40c25b7dc05c86f03400f7bc057638ad484ea", "42d6f43b41c1531853b76c80ab719bf09836710f5daa48ee6a8d7aa1df00e2437530e5585eea98bddbde6526c5f14fd8"],
            127: ["6e0e6b320e9e455581e78a77547404fce0522e4e44255dc7ca1dc2478fb661a6c2e1881606e4ca03b9f24e97df6f64ce", "20f4a690a8f5d3930c408ccf4cdc214f166af0befc2ee69d882c83b1237478d7b23a5da3ea08f477396e82f9829ff717"],
            128: ["2dc037e22e843f1e4660f92954ef7f764ac419509df46f9b9d0a54a11271bf31f1a9356b2f30c69934431a84ecc68f2e", "6630863d66ccf9e92939a540e52c190325a5ab5c790d75be1852f809892f278900620e7631b66aa89e5334b463a02a10"],
            136: ["129b98437fd7961ccc617d6567656aec67623b4290f8b5c8d7b8a8f04745cdb9dc12e3d3a139530430984bed1c430a66", "8208b8b86c5ab72ff72bab06fe49f1be15a2e2eaba08bc56801b4211bb418e6459bfc3dbeb67219501f0e666e108881d"],
            137: ["85e02792835ad28ea537ed34a4272dee5b7bfd4515edea61e707e236de7dd88bdc3a987e3be6d37f8822c4ac249b44bd", "2a5dd7a193b91252232925ef811eac053cacb596fc43153deb6164d1b63c39ba6d82312cd16d4cc4a84716892f8119b4"],
            1000: ["4e7b32811af4e2d9f8f4c414af578a99daf3a5e37d9dd1f0844eab643a62946e3a3a15e5788557b133ef96490efd9b44", "afab869e3c309a8bdd13559b2066aa369b646fb791dc0e57267c6455f6947f1da24348679803f97f26bfb853d1af4147"],
        ],
        "sha3-512": [
            0: ["7539119b6367aa902bdc6f558d20c906d6acbd4aba3fd344eb08b0200144a1fa453ff6e7919962358be53f6db2a320d1852c52a3dea3e907070775f7a91f1282", "b5534e2a08f38a368782bac3505b9d8a1c2153fe67ea7a56d736582a6785eee46f2a1dc0ef99b013b56054312255af82daaa90c6c611d3137e2e18dc1dbee542"],
            1: ["045f86794d71c9c03466891254242d3665785025a21995356e201e6e25fb1cd2e819ff54a70467906fcfef33159e237dd7ee157d95c6584463319879502e0d9c", "f71562ae19ef216035c46bcb15da9df9960391f5da2643582025e32c5611fd53cb833730af618554488c58515ebbb9aba6c1633accf335ba70ae26b5e60c8893"],
            63: ["9d3482a80985b0264dcd7367ea6cb1b7221c4f934448e4a63410c6e314fcfb1e036d72fe7f9215280ffe8dbb8578c0a0f37d6a7dab28b2b3d89ec3855ad15919", "0f49c4de3c852bce3935e2d89398f75a5c674e2f484d474af0885b9f6d4ae532c8778f5239f101474e41afa5627f5ec43aacf41d096e6ec8396c2ed7f5af4fca"],
            127: ["5e7c1bbe5c9e9617fa705ace33ca228cdea15e1bacf5b44e6020004a317c0c7587ee8c6bdf5b56b00d6d8f4a3438cedeaae76e79d820867fa163b69d1e957f79", "4272ff4d678463d9f9d96a35a2b62b15a88d802dd5cc1ac6d65856b3574e797e1392fc91ed07a8a1985385e1a493a09eabe21bfb738c911a6345759f56771fa7"],
            128: ["b921e288cdfbbae6ab9f6d8576083d6bcccff430c421dfe91e8b215a9d4bddd48f5b979eecf065a4396241b41e32431f90bb57913ee6c76fbdc354d8a4bbdc0b", "4da64e333846373b1acedece0e8b6ca3c03e43a47458c33658d1337646ea3e9e39e786f344b248407f88b9cfe01968df27f1db2ca4c65d061767c7256768b867"],
            136: ["baf522165b45ad63a3f6550b94b236d4e0b657d99b7a53722a849785a40d76c39eef32fe58d3a087a106e6b82623ddd83893814ac9c819edc48e0fb564549744", "40bb336529cc614519fee5ff23580c8bf38fe501e1f13fdeda30183ff702775bd56e2dd84fa90223cec8704b36af9a795b790aa383cf62bf6ec954a9c5097238"],
            137: ["ba725566cea30312a39868af83e99f3050d0fc5b93fc1aa6de5fe6a61489ef57951fd14328d48afd5f9687a41387826f9c03f494b91d6a90bb1815a1a453b23c", "5265cbc6d9db6e0d73e8a3d12a8f4874d23b9ea5fc9588cbc3b3fb90e6813c3119696941f787f0c3796163d851048a158f93a303fac21682e04c0b6fed90e281"],
            1000: ["da5eb391d704fed6812f5165e3eec7c1c285b9a84b8614d6dbfa0723982545bb0f63fed3ff47540ca62dfe26aadeeecee4da49e3c154f92f5551ff31720eda72", "a177167a0b6122fc316c15ae06e02a34002f9e701c2e46edce837fbce81606eb1a79ce82aecdc3558423f8fe521bcdeef854e14dc4cd875b549a0e79b473eb92"],
        ],
        "blake2b512": [
            0: ["019fe04bf010b8d72772e6b46897ecf74b4878c394ff2c4d5cfa0b7cc9bbefcb28c36de23cef03089db9c3d900468c89804f135e9fdef7ec9b3c7abe50ed33d3", "714aefeaefedb84eefc9194e168844cf033e2f2bf252c8324660e15b85d74499e27b6b8afc211db5cdfce3d308553cc41ca6f37787fdd87387c4619468834f08"],
            1: ["b86c08ad7f1b408d7bf8496fdd147ea4a2fc18a7a89d15fc39adc54b415bd543b13ba0470785da2bd79e89be8c7652473e271851af84ca8d8446118b45830871", "079f12703d970731b8dc30fb285da1f1f3d062bd10f219db784d822ca69f265e9b324e5b53356f87b112ef57fbf2e99288cf94846e537a254dc72b77debe2323"],
            63: ["7dbe17cffd501927e64a840253387f8c1dd1b56ed8b9ca73711dbb71a1b66ca8365c0304afffe9b4df669fba2cb2ccf74d6c2e20bd27ad26c4494b353afc69d2", "e87582ed4b7f022e54de979a54521975f711ed5924c26a7b3e38f8e442f3661aef44885ff5d6107951bafb82966884db5597314f650c2f0d97efbcdd171b4313"],
            127: ["4bf68c587803172623d682be78c43a2e1475112a0702345e1cfdd272c4544eed4ce4c16b67b4c58746d3dcdf32e2d69b31bae51455ea029c39ee3cf1a54575c9", "25defb53d883e938e90ed2e8e133e9ed74ccef629938a2975b0da4ae3f31ba503ca748183a2bda2d9aacd7225267c42de27442501b8955c1e41d07605267da69"],
            128: ["900ac7eeb5d60bb651fd1bc06c549a9e35d5a90b2cb7343837c92cdb87275df4dcabe3273034e5bd0366410cbd5a6bf147f89818d231505d2186095d9a825ca5", "d15a19b99fe4aede09f65ee02955c04155d222611f91ce933396462cfee2296b77b65baf03d0a3649c0c9e75fe8cc99c12e2855f9b9d45734ebf9e8f3e5bcfcb"],
            136: ["be71fb706d3245c55087dc7766d29028cec7d537602eed2c92556acade3b0ed77db2ddf3ea1c8f5f43b2c17791d7732e75f273faa3c8cc0c86a6ae548de3b93c", "d152a639c7a9c3a2a246d8a30d3f900c110ae7d1fc0f0bd71c39c596aa183807f45507e0a7b2a5261d1d49a5cebcdde8422d3022f2f7902359deb09b63b05d55"],
            137: ["d04194adc9848e0716bcf4906ad11ceb2c76f5a45ab51a0a56c0ad1f548e2e7d5f4fce4f06736a20cdf76f0bd00ea10c1466c75d144b0000e9e8cec9c4333f4f", "378aece5c8426f883b73f28167ed47fdf2445d6e5e5d72ba59a9b4c6ef5ad8b022cd7f216c871afd0025aad3ebd6ebb81d293c7efb769bb08eb1f1c5f3b73ebc"],
            1000: ["d683f49cf2e6816ba3d56bec2548152ea174607be8a606b2b112e66c65fe13ab3ec0062e53f7aa0aaf0cb22a2a5ae25b072fe35b025f42c1042aebd35b822d29", "1a1b8a0eeb96ba7d341883ed20bcb24adc27df4cdaa11cd260579e6b9e37dcd08559630f5d840626d26e09be30a35ea1d821f449a8a96243a9b08d2a9ed22ca1"],
        ],
        "blake2s256": [
            0: ["67148074efc0f6741b474ef81c4d98d266e880d372fe723d2569b1d414d234be", "aa28b07b01753da89792870b28ec5b2c0604bf073b92a033d585181ddf4e16c4"],
            1: ["59c08ce5906ea1bc91d4fd0b91f3b6cefec8da79855e346e580794167b6ab6d5", "a1b1130433a389d122f8a1c119034c073732c45db75377ee4a12b49ddde52b96"],
            63: ["9fa347c4dff1b38a2fdb364df3c4dcb0d2772a1c710c985322bb9549b0f99a22", "d1f1f24635c2f96abd606a8d442d7488f61d852d470ed59266795cc42f48ff25"],
            127: ["d3da7c55ea9fab8bd711cfbca75d5266598c49701c1374060d6e393bd106e6ab", "723e8b19b4c3d731118802e97ec423e7dc4ca4ef3ba6c83688d1b16c4d02d950"],
            128: ["48262952a14096354a5a1f81016b8ef7be570a33f52537af756bf318429a7092", "b2a10958258c9982ffb1831bf721934d99b2466e0559e195b1f7c06dd8049a7e"],
            136: ["425985a86e6dd1c7d6148cbd0b9ab27ac7e4e21d483b61445161831a77877fd0", "cb3bbd649c44d88afed0cb5915de65dceee04c6bf4ac2fae018623961ee00dad"],
            137: ["5412bcbc49f7f687dbd388bc9c59e7dbc61dafa75a1cc78310d5ea052ba96e44", "d9c3c0ffb72c52755bdaf3eec70762e8b4e87f5dd51e3815ca68eb920bdf360c"],
            1000: ["0d56b0dccb7f83a492be387b08f09274e525ba90af15f2748218db96009cc05b", "1870a6cb162ac02d4fbf2c3fb7ca40de89122a3ab7eb93640bcfe179c5fb121e"],
        ],
    ]

    @Test
    func hmacMatchesReferenceIncludingKeysLongerThanTheBlock() {
        for (algorithm, vectors) in Self.hmacs {
            for (length, expected) in vectors {
                // 鍵 "key"（ブロック長より短い）と、200 バイト（全アルゴリズムのブロック長を超える。sha3-224 の 144 も）。
                let keys = [hex(Data("key".utf8)), hex(pattern(200))]
                for (index, key) in keys.enumerated() {
                    let outcome = extraCall("HMAC", [algorithm, key, hex(pattern(length)), "--key-in=hex", "--data-in=hex"])
                    #expect(outcome.status == 200 && outcome.result == expected[index], "\(algorithm) \(length) key\(index): \(outcome.result ?? outcome.error ?? "")")
                }
            }
        }
    }

    @Test
    func largeFilesAreStreamedThroughDigestAndHMAC() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ourin-hashextra-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // 読み込みの単位（1MiB）をまたぎ、どのブロック長にも割り切れない大きさ。
        let large = Data((0..<(3 * 1024 * 1024 + 17)).map { UInt8(truncatingIfNeeded: $0 * 7 + 3) })
        try large.write(to: root.appendingPathComponent("large.bin"))
        let ghost = InternalSaoriContext(ghostRoot: root, deliverEvent: nil)
        let expectedDigests: [String: String] = [
            "sha512-256": "47e6a1dc56486e19ba3b4aeeaa79ae81438d9f1e296293f442d290a874c2a988",
            "sha3-224": "da41c2055750c36ff029da7d36a235833adb582bcc05fe53e0546e17",
            "sha3-256": "101b581a8e742a3c72b9050455d709b2e11a3fa4f227a48bc5ddfc636489f04d",
            "sha3-384": "5007e8fd060b77954affb6d34827ec3350dad202744f8af54887744daa25fe07666fa9f111eb90992f7ff7f58523b75f",
            "sha3-512": "d5bf31b34dea771ff707f97050e44c74f26d54e275699d9ba5d2ccd1c369b49b66b57e54220e8db6f69f230b1ce4b0dcc2f7e91382b3a46f122d7b799c5fef16",
            "blake2b512": "860361258c16bc3ee4ec6a1e4cc89255d04cc48bb8b66e6e46a2ca77a24c36c936105b8125f2bbeb17413da02485bb0a00cce779bd422d855b56ced630bb5ebc",
            "blake2s256": "ccb8cacfc97913cc2bcef6bae3556f7ef791a269e16419bd28c38f4a316d8c3f",
        ]
        let expectedHMACs: [String: String] = [
            "sha512-256": "de24945e31c16ab051cfe8ef492b48a918706bea847dfa3500eeac08674dacf4",
            "sha3-224": "089a3dd08a1634dfd35a5166a972be738c47ce0bc7dc825ee8b29bef",
            "sha3-256": "e544bebf0dc5952a7619abfee4a16617011a3b7a749c60b3a299426f01fc0402",
            "sha3-384": "0ffa376b2e2a993e214b291416d8496dc9f8495c30bb4a1e3ad89b7bf7fe8e54d4551161c3a742a850c7f0bd91c8367d",
            "sha3-512": "5b4deaf76c714f24afbedb6f2846b26edd949bee87d52fb0380356a9aa9133d0bec3cdec8a4809db44fd88a50df868098e223d082791a34cb9d703adc57a5527",
            "blake2b512": "7e5ada302ada5c381f2ae8b0ab21d967676246fbc229e144a7ec4106c0f5df1e6a3184ee719fad59033532fd4493acbb6eac387daabe93dcaeee197ef9f5051a",
            "blake2s256": "35ebd69c814ef12d895ee06701a0365dbfcbc649babaf917414b95a779cd93bb",
        ]
        for algorithm in extraAlgorithms {
            extraOK(extraCall("Digest", [algorithm, "large.bin", "--data-in=file"], context: ghost), expectedDigests[algorithm]!)
            extraOK(extraCall("HMAC", [algorithm, "secret", "large.bin", "--data-in=file"], context: ghost), expectedHMACs[algorithm]!)
        }
    }

    @Test
    func pbkdf2MatchesReference() {
        extraOK(extraCall("DeriveKey", ["pbkdf2", "password", "salt", "20", "--digest=sha512-256", "--iterations=1"]), "4b6a63117d3ec0032624616082c1c1912f56fa5f")
        extraOK(extraCall("DeriveKey", ["pbkdf2", "password", "salt", "100", "--digest=sha512-256", "--iterations=3"]), "9fa42ea03f8f8ac08be344def79d9c031e8f773f20a1061f5f38b37f01d32943ddc662e95a95dd1ee33d0ef16cd3659b2c56894edf8eff95e7190aa14f1b527334faf695e70ccd0ee359c8b18fdaeacf99eb0c8797c215bc0389725511c0e624a656d6a0")
        extraOK(extraCall("DeriveKey", ["pbkdf2", "password", "salt", "20", "--digest=sha3-224", "--iterations=1"]), "d36cad0feea8cf942860130463093a623bead21f")
        extraOK(extraCall("DeriveKey", ["pbkdf2", "password", "salt", "100", "--digest=sha3-224", "--iterations=3"]), "78f53c723000c6648b2685ceb66277b3bbc3830063b32ac0983a42f1c289f0975bc974581baea9fe612300abe1ef25988eb3144d536c99d2b303dffbd56da6337042de3bcdc60f5cb037355e85e209e595edff0b723544ddf6c1e8c5c4270d6a2512064d")
        extraOK(extraCall("DeriveKey", ["pbkdf2", "password", "salt", "20", "--digest=sha3-256", "--iterations=1"]), "94613f3ee2ea730e0b06754f3fc816d4f87c9be9")
        extraOK(extraCall("DeriveKey", ["pbkdf2", "password", "salt", "100", "--digest=sha3-256", "--iterations=3"]), "6677065466c97fdef1c15ae8d95020ca948334f53eceeafc6115ddf405f6d6a4f75ba13a75082d8d8fcb40b84521ea7a5de36e6be040e41888894f7ee7abed7e918ea792fe8d5bf717b47f63e5142d4f78e5b1d59c3e556ead6d25d9c19720eb1305bc13")
        extraOK(extraCall("DeriveKey", ["pbkdf2", "password", "salt", "20", "--digest=sha3-384", "--iterations=1"]), "7d7aba341e6ac84e9938f0f5a2f63c07daa3e058")
        extraOK(extraCall("DeriveKey", ["pbkdf2", "password", "salt", "100", "--digest=sha3-384", "--iterations=3"]), "3c7efe23b2a10f89837270324712c2e0bd8559d6c8ed070268239a2c2abb777b9adc611d71d2b5336ec5101128c285a38933b94d3fa28093c8117116fa7eea2b901d189db89d3ecd540d8800960f7800c98632cc471b4be2cba81d25237bf8345e391a47")
        extraOK(extraCall("DeriveKey", ["pbkdf2", "password", "salt", "20", "--digest=sha3-512", "--iterations=1"]), "f7a2684630ec0f81f23abbf606278deeaad1a350")
        extraOK(extraCall("DeriveKey", ["pbkdf2", "password", "salt", "100", "--digest=sha3-512", "--iterations=3"]), "cf022071b51477a7783157cbf39fe43377494e295da4d9bb8905117d0a4e998c6c930d02e1291e83dee21ffc71163fed3dc6fce250fd476214815e7ccdaccf86f91fe5d8cebeeb6d589100b4943c6fc6d8eeaddaf482a168f8b1e75a7a611e6b363adea3")
        extraOK(extraCall("DeriveKey", ["pbkdf2", "password", "salt", "20", "--digest=blake2b512", "--iterations=1"]), "684e7cc1dd9b241d2c977f38a896645da49b85eb")
        extraOK(extraCall("DeriveKey", ["pbkdf2", "password", "salt", "100", "--digest=blake2b512", "--iterations=3"]), "0543fd2a48f0d9ecdec59863cf9234bfbb1d35cc76df3ae571a069591f95f29c1c4e14d8c194c951678478d714c55544bc5c9db6a9bc19388404c00b9d77a1ce910511ec915cd39cc42fdb3c3686dcd952c911fe94ca0d410da52652fbd71e87d4678a7b")
        extraOK(extraCall("DeriveKey", ["pbkdf2", "password", "salt", "20", "--digest=blake2s256", "--iterations=1"]), "ed939d6f351dddb69f591aa693d75eccaab7c8f5")
        extraOK(extraCall("DeriveKey", ["pbkdf2", "password", "salt", "100", "--digest=blake2s256", "--iterations=3"]), "9f84af2eacd0690a30558c9d31363c6828015792b820bd4fa8e4e7c4f179110d57ccc2453584cff958a54662a85014845902b864dfdba9b2b171d7c8cebba2ca38521d4ec08ae8af107eb6f2d0b561e9435d0188681407c74751bdded469ea358ecd6f62")
        extraFails(extraCall("DeriveKey", ["pbkdf2", "p", "s", "16", "--digest=md5", "--iterations=1"]), 400, "unsupported algorithm")
    }

    @Test
    func hkdfMatchesReference() {
        extraOK(extraCall("DeriveKey", ["hkdf", "input-key-material", "some-salt", "100", "--digest=sha512-256", "--info=ctx"]), "505c83b9ac787879483978af5478a57ab987807ed665264382d061ef7aa75e46f2a2448cbbb4b175c1ebb33b2ac413f27a7dc98c962b052b4ab738949a3bfe5c2b700f29a624044043c5de2cb82f9f11bdf7a17643f7f06bda4e5798746dddad34478e2d")
        extraOK(extraCall("DeriveKey", ["hkdf-extract", "input-key-material", "some-salt", "32", "--digest=sha512-256"]), "c0e0e891a04336ebac60dd25bd4352df10d4444f3d13b64bad6469fe18e50323")
        extraOK(extraCall("DeriveKey", ["hkdf-expand", "c0e0e891a04336ebac60dd25bd4352df10d4444f3d13b64bad6469fe18e50323", "", "100", "--password-in=hex", "--digest=sha512-256", "--info=ctx"]), "505c83b9ac787879483978af5478a57ab987807ed665264382d061ef7aa75e46f2a2448cbbb4b175c1ebb33b2ac413f27a7dc98c962b052b4ab738949a3bfe5c2b700f29a624044043c5de2cb82f9f11bdf7a17643f7f06bda4e5798746dddad34478e2d")
        extraOK(extraCall("DeriveKey", ["hkdf", "input-key-material", "", "96", "--digest=sha512-256"]), "7e685453aac068090ab19adb0ded32849d3065e7307f97abeeb9137668d96be6ce6ec1a9ec0bfab968d2db0efc84e9f62540637b2cc35143a4b6a355e0f1e5927e7d95e17c83fe90f9ec67e2d93053f6a4ec60758dc1e104b324d761be59641c")
        #expect(extraCall("DeriveKey", ["hkdf", "ikm", "s", "1024", "--digest=sha512-256"]).status == 200)
        extraFails(extraCall("DeriveKey", ["hkdf-extract", "ikm", "s", "33", "--digest=sha512-256"]), 400, "out of range")
        extraOK(extraCall("DeriveKey", ["hkdf", "input-key-material", "some-salt", "100", "--digest=sha3-224", "--info=ctx"]), "8e4f6af71063f23d517933d95ee42618889f49e4cb5b5fe149f187c18d1eecaf62689db5bae0a699aa31c8da0f86846edbdcb551c93de7a75c447c3112c4b4e091f954758143acab51b90fc041976bf1a1ab2af58c50b6ceaceda4d3f986db23f53d5094")
        extraOK(extraCall("DeriveKey", ["hkdf-extract", "input-key-material", "some-salt", "28", "--digest=sha3-224"]), "8864dcfa1893d1129ad31dc4134813ad6956e4b1a96a959beb86a4ef")
        extraOK(extraCall("DeriveKey", ["hkdf-expand", "8864dcfa1893d1129ad31dc4134813ad6956e4b1a96a959beb86a4ef", "", "100", "--password-in=hex", "--digest=sha3-224", "--info=ctx"]), "8e4f6af71063f23d517933d95ee42618889f49e4cb5b5fe149f187c18d1eecaf62689db5bae0a699aa31c8da0f86846edbdcb551c93de7a75c447c3112c4b4e091f954758143acab51b90fc041976bf1a1ab2af58c50b6ceaceda4d3f986db23f53d5094")
        extraOK(extraCall("DeriveKey", ["hkdf", "input-key-material", "", "84", "--digest=sha3-224"]), "18b0a5a5bb565e8256b417523f74ea1cc6e571444f3197aa5c31de3cd8ebae11a47249631aeb58a2d8c65217c07d671bf849374fb8fbf202994ddc96a1979688341dfceb31049ac93206b49594908901051b034d")
        #expect(extraCall("DeriveKey", ["hkdf", "ikm", "s", "1024", "--digest=sha3-224"]).status == 200)
        extraFails(extraCall("DeriveKey", ["hkdf-extract", "ikm", "s", "29", "--digest=sha3-224"]), 400, "out of range")
        extraOK(extraCall("DeriveKey", ["hkdf", "input-key-material", "some-salt", "100", "--digest=sha3-256", "--info=ctx"]), "e4b32412637f39b3d65dd591b2283d2c3553943b842fce9cb3a598a213170bde09db58a11ea710c2fd3bc3b074c09bec726b40cd07f3c2da4e0167b9ddbbb683b765e1d28a2fb49d68349877b4cf6051dfd1a46eb0ed8d73feee2dd079224672960f9e8e")
        extraOK(extraCall("DeriveKey", ["hkdf-extract", "input-key-material", "some-salt", "32", "--digest=sha3-256"]), "6c9164a469c230a9dd45350f85f51c59403133d0ddcfb1ba2dba3d2c7c4921fa")
        extraOK(extraCall("DeriveKey", ["hkdf-expand", "6c9164a469c230a9dd45350f85f51c59403133d0ddcfb1ba2dba3d2c7c4921fa", "", "100", "--password-in=hex", "--digest=sha3-256", "--info=ctx"]), "e4b32412637f39b3d65dd591b2283d2c3553943b842fce9cb3a598a213170bde09db58a11ea710c2fd3bc3b074c09bec726b40cd07f3c2da4e0167b9ddbbb683b765e1d28a2fb49d68349877b4cf6051dfd1a46eb0ed8d73feee2dd079224672960f9e8e")
        extraOK(extraCall("DeriveKey", ["hkdf", "input-key-material", "", "96", "--digest=sha3-256"]), "b902834f0b2041e3160ee4c87c27760673e21a4965b90d6bb649c77f14dc65958226cd142f22c262f7733c80a9d299964291c49fbf2eaaccb9746fdf83d6b3b934c7daa982eaf572957edcd4f295dd26538d334fdbb90a640e91f51251f7cc11")
        #expect(extraCall("DeriveKey", ["hkdf", "ikm", "s", "1024", "--digest=sha3-256"]).status == 200)
        extraFails(extraCall("DeriveKey", ["hkdf-extract", "ikm", "s", "33", "--digest=sha3-256"]), 400, "out of range")
        extraOK(extraCall("DeriveKey", ["hkdf", "input-key-material", "some-salt", "100", "--digest=sha3-384", "--info=ctx"]), "8b6ad68b0679ac69212b93ddbb166f4a7dc2d187e9d925cc8ad54f7affb9e096c30b1dfb2c0164ac9b019ac099293316b15e12b156a54671239cee8e3f950ec9c09b118ece17470f7565c55af4dceccaab7c3be7bab02517a0963eb2e00f1a55e651bf52")
        extraOK(extraCall("DeriveKey", ["hkdf-extract", "input-key-material", "some-salt", "48", "--digest=sha3-384"]), "0d0df425e384ab54aeacfa0ab7d2b28c0522c5972ddd391870bafef75bbf30b76d115a8f65462bb17a72fd2b8dbb8496")
        extraOK(extraCall("DeriveKey", ["hkdf-expand", "0d0df425e384ab54aeacfa0ab7d2b28c0522c5972ddd391870bafef75bbf30b76d115a8f65462bb17a72fd2b8dbb8496", "", "100", "--password-in=hex", "--digest=sha3-384", "--info=ctx"]), "8b6ad68b0679ac69212b93ddbb166f4a7dc2d187e9d925cc8ad54f7affb9e096c30b1dfb2c0164ac9b019ac099293316b15e12b156a54671239cee8e3f950ec9c09b118ece17470f7565c55af4dceccaab7c3be7bab02517a0963eb2e00f1a55e651bf52")
        extraOK(extraCall("DeriveKey", ["hkdf", "input-key-material", "", "144", "--digest=sha3-384"]), "74faa57be6a3b6dedb0331658664ef4cc7126263cb40f1e415dc7f2cdb8e38f0e509e4b41a31a0a15fbb1c8b0ad40c97908389d6acff19da2eb0ee469e91916267bae6a90fa33694b3d1d204cb78d996b57c00712c784d244ad8e597eedbfc0ff4e8b5ccdb33c2c4a49bcaba6078cdf9056d77f360b1298602ba8c3ee8a4b25341899350d88505a93794b828b6537be8")
        #expect(extraCall("DeriveKey", ["hkdf", "ikm", "s", "1024", "--digest=sha3-384"]).status == 200)
        extraFails(extraCall("DeriveKey", ["hkdf-extract", "ikm", "s", "49", "--digest=sha3-384"]), 400, "out of range")
        extraOK(extraCall("DeriveKey", ["hkdf", "input-key-material", "some-salt", "100", "--digest=sha3-512", "--info=ctx"]), "8d81f9ee7a35c01a1a2f63e8779d0d78421535853ab9d2642c198297448d5c817220e1b4e0da71752f4b0fdb7e3750347e3dd535f859ed043e8409e35c5e4323b70b32311d0dfbfde8d7fbffeca98a57e7f0b469ac17645f1e387bf4d3113b1678f6abac")
        extraOK(extraCall("DeriveKey", ["hkdf-extract", "input-key-material", "some-salt", "64", "--digest=sha3-512"]), "b20243a636898eb01a290c145691b9b77dcf9489a40b7e1b2c8db56c8b6dac9ecf260b83ad3ca2695cdae49fce085397eb81dc0b49595e29c347aba72362841c")
        extraOK(extraCall("DeriveKey", ["hkdf-expand", "b20243a636898eb01a290c145691b9b77dcf9489a40b7e1b2c8db56c8b6dac9ecf260b83ad3ca2695cdae49fce085397eb81dc0b49595e29c347aba72362841c", "", "100", "--password-in=hex", "--digest=sha3-512", "--info=ctx"]), "8d81f9ee7a35c01a1a2f63e8779d0d78421535853ab9d2642c198297448d5c817220e1b4e0da71752f4b0fdb7e3750347e3dd535f859ed043e8409e35c5e4323b70b32311d0dfbfde8d7fbffeca98a57e7f0b469ac17645f1e387bf4d3113b1678f6abac")
        extraOK(extraCall("DeriveKey", ["hkdf", "input-key-material", "", "192", "--digest=sha3-512"]), "985ffcea1ac47529ce52082ca6573b5e34054f447486e852c97566ad3862fcae1c15fab1c0f02ee9dade84ea5ad2df27ffe2742b108df826c6879817069877f00a113dcb372c14f030330fcb54a67c38d11bf51233921daa50dbb908473424c81f14c0bf6da504614afb4c1da03c7ca602df3267650f538d3f79b41380284aeb04ec92c64ba1141073b060b3629348c59de4eb46845702c9c0ff9b34e62791bad804eec25fce25472965863e96f94f0aa167ed6fd110b121e9f3a6f7c666c8f6")
        #expect(extraCall("DeriveKey", ["hkdf", "ikm", "s", "1024", "--digest=sha3-512"]).status == 200)
        extraFails(extraCall("DeriveKey", ["hkdf-extract", "ikm", "s", "65", "--digest=sha3-512"]), 400, "out of range")
        extraOK(extraCall("DeriveKey", ["hkdf", "input-key-material", "some-salt", "100", "--digest=blake2b512", "--info=ctx"]), "fd4d61453d0b7bc817ac2bcac1d1e5a78d23bdf36077ccb06d21d9e555c2a4268b5008e0574ac923b66a3afb2018dc466cd9d500ace42960c25015f724a77dc943f61f4a9168ee74c9c6dafb3655f023da2fdbb010ef4ff0de3b329a06b3161a79cf3faf")
        extraOK(extraCall("DeriveKey", ["hkdf-extract", "input-key-material", "some-salt", "64", "--digest=blake2b512"]), "043933eb1ea69484389c88a7a2b74a7f557da7517ff30e955509eab3d1c191138bbaa236e09ec4ed44c3b5220e464ab07eaa0243a3e1eb3bd5aa40131e417c32")
        extraOK(extraCall("DeriveKey", ["hkdf-expand", "043933eb1ea69484389c88a7a2b74a7f557da7517ff30e955509eab3d1c191138bbaa236e09ec4ed44c3b5220e464ab07eaa0243a3e1eb3bd5aa40131e417c32", "", "100", "--password-in=hex", "--digest=blake2b512", "--info=ctx"]), "fd4d61453d0b7bc817ac2bcac1d1e5a78d23bdf36077ccb06d21d9e555c2a4268b5008e0574ac923b66a3afb2018dc466cd9d500ace42960c25015f724a77dc943f61f4a9168ee74c9c6dafb3655f023da2fdbb010ef4ff0de3b329a06b3161a79cf3faf")
        extraOK(extraCall("DeriveKey", ["hkdf", "input-key-material", "", "192", "--digest=blake2b512"]), "1580876a4534c27ab4699802df0fde850316e65b82234cb5f687b27d777d5f719187ecffc98f3000939b704c2fb976230c1e0fa9952d71cc61dde0d60c6986e1372f3e4f6a376868cdc84b089ddd7dd44d66dedbd86a824aea28b2365c79510190a0315003b6afd5c7fa2c847465a4efe5fa02fa8bbf05974805e73867274ebc066d4da7d5afb31806ebb9bd6e04893a0ddf12651bd644dcfc80a754386fc196c11fc8e1a1a54778a08376b72d6a340c13224e477f6f9bce357adc7f238947f7")
        #expect(extraCall("DeriveKey", ["hkdf", "ikm", "s", "1024", "--digest=blake2b512"]).status == 200)
        extraFails(extraCall("DeriveKey", ["hkdf-extract", "ikm", "s", "65", "--digest=blake2b512"]), 400, "out of range")
        extraOK(extraCall("DeriveKey", ["hkdf", "input-key-material", "some-salt", "100", "--digest=blake2s256", "--info=ctx"]), "35624d07a2f90da889c45ced58d3fc8ac4ec7aa4a4c6e3b92310b620292281e328992aabe9b4fe2fc79c623fdd09f5742f0e13ca29491737b9d1bdfc234c7687798ecbe4079c23df7d18d5d20c3605e248efb3dd252791a9adf088c0d8b2ca71684c7e84")
        extraOK(extraCall("DeriveKey", ["hkdf-extract", "input-key-material", "some-salt", "32", "--digest=blake2s256"]), "d781af8c72c5b70ed482787b11d00cc88a00e193ec07606462cc0bcd40178e2b")
        extraOK(extraCall("DeriveKey", ["hkdf-expand", "d781af8c72c5b70ed482787b11d00cc88a00e193ec07606462cc0bcd40178e2b", "", "100", "--password-in=hex", "--digest=blake2s256", "--info=ctx"]), "35624d07a2f90da889c45ced58d3fc8ac4ec7aa4a4c6e3b92310b620292281e328992aabe9b4fe2fc79c623fdd09f5742f0e13ca29491737b9d1bdfc234c7687798ecbe4079c23df7d18d5d20c3605e248efb3dd252791a9adf088c0d8b2ca71684c7e84")
        extraOK(extraCall("DeriveKey", ["hkdf", "input-key-material", "", "96", "--digest=blake2s256"]), "c8866784e1a016a0e53d59357cb95f7806ddda2fc06b87d0743d726ecce5be80a86bb57dcc18f21aec67f9207b0248249ce239170fd16de5d4203ef09256273db3ecc702ae66be06744fc9ad1c82043b13da5860411669632f603f88bc372b94")
        #expect(extraCall("DeriveKey", ["hkdf", "ikm", "s", "1024", "--digest=blake2s256"]).status == 200)
        extraFails(extraCall("DeriveKey", ["hkdf-extract", "ikm", "s", "33", "--digest=blake2s256"]), 400, "out of range")
    }

    @Test
    func totpMatchesReference() {
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=59", "--digits=8", "--digest=sha512-256"]), "00441233")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=1111111109", "--digits=8", "--digest=sha512-256"]), "97406494")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=20000000000", "--digits=8", "--digest=sha512-256"]), "83211259")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=59", "--digits=8", "--digest=sha3-224"]), "36946527")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=1111111109", "--digits=8", "--digest=sha3-224"]), "13216597")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=20000000000", "--digits=8", "--digest=sha3-224"]), "59401467")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=59", "--digits=8", "--digest=sha3-256"]), "03503818")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=1111111109", "--digits=8", "--digest=sha3-256"]), "00384900")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=20000000000", "--digits=8", "--digest=sha3-256"]), "23378950")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=59", "--digits=8", "--digest=sha3-384"]), "66214681")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=1111111109", "--digits=8", "--digest=sha3-384"]), "30811795")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=20000000000", "--digits=8", "--digest=sha3-384"]), "44025224")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=59", "--digits=8", "--digest=sha3-512"]), "02747274")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=1111111109", "--digits=8", "--digest=sha3-512"]), "79213086")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=20000000000", "--digits=8", "--digest=sha3-512"]), "84576074")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=59", "--digits=8", "--digest=blake2b512"]), "13203303")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=1111111109", "--digits=8", "--digest=blake2b512"]), "55622833")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=20000000000", "--digits=8", "--digest=blake2b512"]), "35438159")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=59", "--digits=8", "--digest=blake2s256"]), "91948900")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=1111111109", "--digits=8", "--digest=blake2s256"]), "68091993")
        extraOK(extraCall("TOTP", ["12345678901234567890123456789012", "--key-in=text", "--time=20000000000", "--digits=8", "--digest=blake2s256"]), "09671488")
    }
}
