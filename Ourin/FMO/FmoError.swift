// FMO 操作で発生し得るエラーを表す列挙型
import Foundation

enum FmoError: Error {
    case alreadyRunning
    case systemError(String)
}
