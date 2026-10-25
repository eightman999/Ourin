ScriptBridge — 他の伺か形式のスクリプトを解釈して再生する Ourin 用プラグイン

■ 使い方
・プラグインメニューから ScriptBridge を選ぶと、scripts フォルダのファイルが選択肢で並びます。
・ゴーストからは \![raiseplugin,scriptbridge,OnScriptBridgePlay,ファイル名,エントリ名,形式] で呼べます。
    ファイル名 … scripts フォルダからの相対パス（またはフルパス）
    エントリ名 … 里々の ＊名前、華和梨のエントリ、AYA の関数名。省略時はランダムトーク
                  （里々: 名前なしの ＊、華和梨: sentence、AYA: OnAiTalk → RandomTalk）
    形式       … auto / satori / kawari / aya / sakura。省略時は拡張子と内容から判定
・OnScriptBridgeEval は Reference0 の本文をその場で解釈します（本文の改行は U+0001 で渡す）。
・OnScriptBridgeConvert は Reference0 の旧仕様タグを現行タグに変換し、Value で返します。

■ 解釈する構文（基本構文のみ）
・里々: ＊トーク / ＠単語群 / （単語群名） / 行頭 ： の話者切替 / ＃コメント
・華和梨: 名前 : 単語 , 単語 / ${名前} / # コメント。=kis〜=end と $(KIS コマンド) は実行しません。
・AYA / YAYA: 関数名 { "候補" "候補" } / %(関数名) / コメント。式・変数・制御構文は実行しません。
・さくらスクリプトのテキスト: 空行で区切ったブロックから 1 つを再生します。
・文字コードは UTF-8 / Shift_JIS(CP932) を自動判定します。

■ 後方互換（すべての出力に適用。UKADOC さくらスクリプトリストの[旧仕様]を現行の書き方へ）
  \q[ID][タイトル] / \q*[ID][タイトル] → \q[タイトル,ID]\n
  \z → \e        \a → \![raise,OnAITalk]
  \__t → \![open,teachbox]    \__c → \![open,communicatebox]
  \_!〜\_! → \_?〜\_?          \![reloadsurface] → \![reload,shell]
  \![move,X,Y,時間,基準,基準位置,移動位置] → \![move,--X=…,--Y=…,--time=…,--base=…,…]
  （moveasync も同様。fix / 省略した座標は書きません）
