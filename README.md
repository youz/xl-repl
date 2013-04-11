# xl-repl

lisp-repl-mode for [xyzzy](http://www.jsdlab.co.jp/~kamei/)


## Install

- NetInstallerをよりインストール
 
    下記のURLのパッケージリストを登録し、パッケージ`*scrap*`よりインストールして下さい。

    http://youz.github.io/xyzzy/packages.l

- 手動インストール

    `git clone git://github.com/youz/xl-repl.git` でソースツリーをコピーし、
    コピー先のパスを`*load-path*`へ追加して下さい。

        ;; 設定例 (.xyzzy もしくは site-lisp/siteinit.l へ追記)
        (push "C:/path/to/xl-repl/site-lisp" *load-path*)

- (共通) `.xyzzy` or `site-lisp/siteinit.l` の設定

        (require "xl-repl")
        ; ldoc, ldoc2 を使っている場合
        (push 'ed:lisp-repl-mode ed::*ldoc-activated-mode-list*)
        ; ac-mode を使っている場合
        (push 'ed:lisp-repl-mode ed::*ac-mode-lisp-mode*)


## Usage

    M-x start-repl


## Keymap

REPLバッファ用キーマップ `repl:*keymap*` は、 `ed:*lisp-mode-map*` をベースにして
以下のキーバインドを追加/上書きしています。

- Return -- repl::newline-or-eval-input  (入力した式を評価 or 改行&インデント)
  * `repl:*return-behavior*` の値によって動作を切り替え (後述)
- C-j -- lisp-newline-and-indent  (lisp-modeのReturnと同じ)
- C-l -- repl::clear-repl  (REPLバッファをクリア)
- C-h -- repl::repl-backward-delete-char
- C-d, Delete -- repl::repl-delete-char-or-selection
- C-a, Home -- repl::repl-goto-bol
- C-c C-u -- repl::kill-current-input (入力中の式をkill-region)
- C-c C-n -- repl::goto-next-prompt (次のプロンプトへ移動)
- C-c C-p -- repl::goto-next-prompt (前のプロンプトへ移動)
- M-C-a -- repl::beginning-of-input  (入力中の式の先頭へ移動)
- M-C-e -- repl::end-of-input  (入力中の式の最後へ移動)
- M-n -- repl::next-input  (入力履歴 - 進む)
- M-p -- repl::previous-input  (入力履歴 - 戻る)

## Costomize

カスタマイズ用変数について。

- `repl:*buffer-name*`

  * REPLバッファ名称

- `repl:*greeting*`

  * REPLバッファ先頭に表示するメッセージ

- `repl:*prompt*`

  * プロンプト文字列。以下の変数が使えます。
  * `%p` -- カレントパッケージ名
  * `%d` -- カレントディレクトリ (default-directory)
  * `%u` -- Windowsユーザーネーム (user-name)
  * `%m` -- PC名 (mathine-name)
  * `%o` -- OS名 (os-platform)
  * `%v` -- xyzzyのバージョン (software-version)
  * `%n` -- ソフト名 (software-type)

- `repl:*prompt-style*`, `repl:*stdout-style*`, `repl:*values-style*`, `repl:*error-style*`

  * プロンプト、標準出力、評価値、エラーメッセージの表示色・装飾
  * set-text-attributeのキーワード引数の形で指定します。

- `repl:*return-behavior*`

  * 入力式中でのReturn押下時の動作を切り替えます。
  * :send-if-complete -- 入力式が完成していれば、カーソルが式途中にあっても評価実行
  * :send-only-if-after-complete -- カーソルが入力式の後ろにある場合のみ評価実行
  * 入力式が未完成の場合は常にlisp-newline-and-indentを実行します。

### 設定例

    (setq repl:*prompt-style* '(:foreground 14 :bold t)
          repl:*error-style* '(:foreground 9)
          repl:*return-behavior* :send-only-if-after-complete)


## REPL Command

以下のキーワードシンボル(と引数)を入力するとREPLコマンドを実行します。

    :calc (&rest exprs)
        ; exprsをcalc-modeの計算式として評価

    :cd (&optional dir)
        ; default-directoryをdirへ移動 (dir省略時はdefault-directoryを表示)

    :clip (form)
        ; formを評価し、*standard-output*への出力をクリップボードへコピー

    :describe (symbol-or-package-name)
        ; パッケージ/変数/定数/関数の説明を表示

    :dir (&optional wildcard)
        ; default-directoryのファイルを列挙

    :expand (form)
        ; formをmacroexpandして表示

    :help (&optional pattern)
        ; REPLコマンドの説明を表示

    :load (name)
        ; *load-path*にdefault-directoryを含めて(load-library 'name)を評価

    :log (form)
        ; ログ取り用バッファストリームをレキシカル変数*log*に束縛してformを評価

    :ls (&optional pat (pkg *package*))
        ; パッケージ内の変数/定数/関数シンボルを列挙

    :lsall (&optional pattern)
        ; 全パッケージの変数/定数/関数シンボルを列挙

    :lscmd (&optional pattern)
        ; コマンド名を列挙

    :lsext (&optional pattern (pkg *package*))
        ; パッケージよりexportされている変数/定数/関数シンボルを列挙

    :lspkg (&optional pattern)
        ; パッケージ名を列挙 (nicknamesがあれば括弧内に表示)

    :mkpkg (name &rest options)
        ; (make-package 'name [options])を評価し、*package*を作成したパッケージに変更

    :package (name)
        ; (in-package 'name)を評価

    :reference (word &rest options)
        ; リファレンスを表示
        ; [オプション]
        ; :part - 部分一致検索
        ; :regexp - 正規表現検索
        ; :fts  - 本文を含めた全文検索

    :require (name)
        ; *load-path*にdefault-directoryを含めて(require 'name)を評価

    :step (form)
        ; formをステップ実行

    :time (form)
        ; formを評価し、実行時間(秒)を表示


適当に省略してもOK。

    user> :pa repl.command     ; :packageコマンド
    #<package: repl.command>
    
    repl.command> :de package  ; :describeコマンド
    <Function> repl.command::package (name)
        ; (in-package 'name)を評価


### Referenceバッファ 操作方法

referenceコマンドで表示されるバッファ上では以下のキーが使用できます。

- j, k -- 1行移動
- J, K -- 記事移動 (:part or :ftsオプションを使用して複数記事表示時)
- q -- referenceバッファを閉じる
- RET, 左クリック -- (マウス)カーソル下のシンボルやseealso項目の記事にジャンプ
- Backspace, Alt+Left -- ジャンプ履歴 戻る
- Alt+Right -- ジャンプ履歴 進む

## Author
Yousuke Ushiki (<citrus.yubeshi@gmail.com>)

[@Yubeshi](http://twitter.com/Yubeshi/)


## Copyright
MIT License を適用しています。

