# xl-repl

lisp-repl-mode for [xyzzy](http://www.jsdlab.co.jp/~kamei/)


## Install

    git clone git://github.com/youz/xl-repl.git

### ~/.xyzzy

    (push "C:/path/to/xl-repl/site-lisp" *load-path*)
    (require "xl-repl")


## Usage

    M-x start-repl


## Keymap

`ed:*lisp-mode-map*` のコピーに以下のキーバインドを上書き

- RET -- repl::newline-or-eval-input
- C-l -- repl::clear-repl
- M-C-a -- repl::beginning-of-input
- M-C-e -- repl::end-of-input


## REPL Command

以下のキーワードシンボル(と引数)を入力するとREPLコマンドを実行します。

    :cd (&optional dir)
        ; default-directoryをdirへ移動 (dir省略時はdefault-directoryを表示)

    :desc (sym)
        ; 変数/定数/関数のdocstringを表示

    :dir (&optional wildcard)
        ; default-directoryのファイルを列挙

    :help (&optional pattern)
        ; REPLコマンドの説明を表示

    :load (name)
        ; default-directoryを*load-path*に含めて(load-library 'name)を評価

    :ls (&optional pat (pkg *package*))
        ; パッケージ内の変数/定数/関数シンボルを列挙

    :lspkg (&optional pattern)
        ; パッケージ名を列挙

    :mkpkg (name &rest options)
        ; (make-package 'name [options])を評価し、*package*を作成したパッケージに変更

    :package (name)
        ; (in-package 'name)を評価

    :require (name)
        ; default-directoryを*load-path*に含めて(require 'name)を評価

    :rmpkg (name)
        ; (delete-apckage 'name)を評価


適当に省略してもOK.

    user> :pa repl.command     ; :packageコマンド
    #<package: repl.command>
    
    repl.command> :de package  ; :descコマンド
    <Function> repl.command::package (name)
        ; (in-package 'name)を評価


## Author
Yousuke Ushiki (<citrus.yubeshi@gmail.com>)

[@Yubeshi](http://twitter.com/Yubeshi/)


## Copyright
MIT License を適用しています。

