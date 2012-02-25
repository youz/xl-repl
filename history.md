# xl-repl 変更履歴


## 2012/02/23  v1.1.0

### 新機能

* 標準出力と評価結果の表示にtext-attributeを適用 (`*stdout-style*`, `*values-style*`)
* `*return-behavior*`の値によってReturn押下時の挙動を切り替えられるようにした
    + :send-if-complete -- 式が完成していれば実行 / 未完成ならlisp-newline-and-indent
    + :send-only-if-after-complete -- カーソルが完成している式の後ろにある場合のみ実行
* キーバインド追加
    + `C-j` -- lisp-newline-and-indent
    + `C-a`,`Home` -- repl::repl-goto-bol (プロンプトを考慮したbeginning-of-line)
    + `C-c C-n` -- repl::goto-next-prompt
    + `C-c C-p` -- repl::goto-previous-prompt
    + `C-c C-u` -- repl::kill-current-input (入力中の式をkill-region)

### 変更点

* 式途中/過去入力/過去評価結果の各表示位置でReturnを押した時の挙動をSLIME風に
    + 式途中 -- `*return-behavior*` によって eval or lisp-newline-and-indent
    + 過去入力 -- 入力式を最後のプロンプトの後ろへコピー
    + 過去評価結果 -- 値を最後のプロンプトの後ろへコピー
* `si:*trace-on-error*` => t の時、`*error-output*`への出力を全て横取りしていたのを
   broadcastを使い、コピーを取得するように変更
* 入力履歴のキーバインドは`M-n`,`M-p`とし、`C-n`,`C-p`は`*lisp-mode-map*`のままにした

## 2012/02/18  v1.0.1

* 評価結果がnilの時に印字されない不具合を修正

## 2012/02/17  v1.0.0

### 新機能

* expandコマンド -- マクロフォームを展開して表示
* timeコマンド -- 処理時間を計測して表示

### 変更点

* ls系コマンドの表示で、カレントパッケージのシンボルにもパッケージ修飾子を付けるように変更
* ls系コマンドの表示で、関数/マクロは引数も表示するように変更
* 評価結果がprint-functionを持つ構造体の場合、format指示子~Aを使って印字するように変更
    [Issue #1](https://github.com/youz/xl-repl/issues/1)

### 修正

* 評価結果が循環参照を含む場合に対応
    [Issue #2](https://github.com/youz/xl-repl/issues/2)
* REPL変数 `/` の内容をCL仕様準拠に変更
    [Issue #4](https://github.com/youz/xl-repl/issues/4)
* 評価結果表示の前にfresh-lineを行うように変更
    [Issue #5](https://github.com/youz/xl-repl/issues/5)


## 2012/02/13  v0.9.0

* αリリース
