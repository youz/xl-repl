# xl-repl

lisp-repl-mode for [xyzzy](http://www.jsdlab.co.jp/~kamei/)


## Install

- NetInstallerをよりインストール
 
    下記のURLのパッケージリストを登録し、パッケージ`*scrap*`よりインストールして下さい。

    http://youz.github.com/xyzzy/package.l

- 手動インストール

    `git clone git://github.com/youz/xl-repl.git` して `~/.xyzzy` に以下の設定を記述

        (push "C:/path/to/xl-repl/site-lisp" *load-path*)
        (require "xl-repl")


## Usage

    M-x start-repl


## Keymap

REPLバッファ用キーマップ `repl:*keymap*` は、 `ed:*lisp-mode-map*` をベースにして
以下のキーバインドを追加/上書きしています。

- RET -- repl::newline-or-eval-input  (入力した式を評価 / 書きかけならlisp-newline-and-indent)
- C-l -- repl::clear-repl  (REPLバッファをクリア)
- M-C-a -- repl::beginning-of-input  (入力中の式の先頭へ移動)
- M-C-e -- repl::end-of-input  (入力中の式の最後へ移動)
- C-p -- repl::previous-input  (入力履歴 - 戻る)
- C-n -- repl::next-input  (入力履歴 - 進む)

## REPL Command

以下のキーワードシンボル(と引数)を入力するとREPLコマンドを実行します。

    :cd (&optional dir)
        ; default-directoryをdirへ移動 (dir省略時はdefault-directoryを表示)

    :describe (symbol-or-package-name)
        ; パッケージ/変数/定数/関数の説明を表示

    :dir (&optional wildcard)
        ; default-directoryのファイルを列挙

    :expand (form)
        ; formをmacroexpandして表示

    :help (&optional pattern)
        ; REPLコマンドの説明を表示

    :load (name)
        ; default-directoryを*load-path*に含めて(load-library 'name)を評価

    :ls (&optional pat (pkg *package*))
        ; パッケージ内の変数/定数/関数シンボルを列挙

    :lsall (&optional pattern)
        ; 全パッケージの変数/定数/関数シンボルを列挙

    :lsext (&optional pattern (pkg *package*))
        ; パッケージよりexportされている変数/定数/関数シンボルを列挙

    :lspkg (&optional pattern)
        ; パッケージ名を列挙 (nicknamesがあれば括弧内に表示)

    :mkpkg (name &rest options)
        ; (make-package 'name [options])を評価し、*package*を作成したパッケージに変更

    :package (name)
        ; (in-package 'name)を評価

    :require (name)
        ; default-directoryを*load-path*に含めて(require 'name)を評価

    :time (form)
        ; formを評価し、実行時間(秒)を表示


適当に省略してもOK。

    user> :pa repl.command     ; :packageコマンド
    #<package: repl.command>
    
    repl.command> :de package  ; :describeコマンド
    <Function> repl.command::package (name)
        ; (in-package 'name)を評価


## Author
Yousuke Ushiki (<citrus.yubeshi@gmail.com>)

[@Yubeshi](http://twitter.com/Yubeshi/)


## Copyright
MIT License を適用しています。

