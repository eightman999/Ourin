import AppKit

/// `\![open,scriptbox]` / `\![open,textareabox]` と `\![close,scriptbox]` の配線。
///
/// scriptbox は SSP 2.8.35f の入力種別（CInputWnd::GetTypeText @0x444d70 の case 1）で、
/// UKADOC 未収録の SSP 拡張。基本 UI と決定・キャンセル時のイベント発火
/// （OnUserInput / OnUserInputCancel）は inputbox と同一のため、単一行の
/// inputbox ダイアログを共用する。`\![close,scriptbox]` も `\![close,inputbox]`
/// と同じく、キャンセルイベントを発生させずに閉じる。
extension GhostManager {
    /// `\![open,scriptbox|textareabox,...]` の引数解析結果。
    struct InputBoxCommand: Equatable {
        let id: String
        let timeoutMs: Int?
        let initialText: String
        /// textareabox のみ使用（`--placeholder=`）。
        let placeholder: String
    }

    /// `\![open,scriptbox|textareabox,ID[,表示時間[,初期文字列]]]` と
    /// `--id=/--timeout=/--text=` 形を、既存の inputbox と同じ優先度で解釈する。
    func parseInputBoxCommand(_ rawArguments: [String], defaultID: String) -> InputBoxCommand {
        let parsed = parseCommandArguments(rawArguments)
        let id = parsed.positionals.first ?? parsed.options["id"] ?? defaultID
        let timeoutMs = parsed.options["timeout"].flatMap(Int.init)
            ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)
        let initialText = parsed.options["text"]
            ?? (parsed.positionals.count >= 3 ? parsed.positionals[2] : "")
        let placeholder = parsed.options["placeholder"] ?? ""
        return InputBoxCommand(id: id, timeoutMs: timeoutMs, initialText: initialText, placeholder: placeholder)
    }

    /// `\![open,scriptbox,ID,表示時間,初期文字列,オプション...]`。
    /// 決定で OnUserInput、取消／タイムアウトで OnUserInputCancel（inputbox と同一）。
    func openScriptBox(fromCommandArguments rawArguments: [String]) {
        let command = parseInputBoxCommand(rawArguments, defaultID: "scriptbox")
        let options = inputDialogOptions(from: rawArguments)
        playbackQueue.append(.deferredCommand { [weak self] in
            self?.showInputBoxDialog(
                id: command.id,
                timeoutMs: command.timeoutMs,
                initialText: command.initialText,
                options: options
            )
        })
    }

    /// `\![open,textareabox,ID,表示時間,テキスト,オプション...]`（UKADOC 2.9.10）。
    func openTextAreaBox(fromCommandArguments rawArguments: [String]) {
        let command = parseInputBoxCommand(rawArguments, defaultID: "textareabox")
        let options = inputDialogOptions(from: rawArguments)
        playbackQueue.append(.deferredCommand { [weak self] in
            self?.showTextAreaBoxDialog(
                id: command.id,
                timeoutMs: command.timeoutMs,
                initialText: Self.textAreaLines(from: command.initialText),
                placeholder: Self.textAreaLines(from: command.placeholder),
                options: options
            )
        })
    }
}
