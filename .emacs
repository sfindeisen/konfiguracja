;; show the full file path in the minibuffer
(defun show-file-name ()
  "Show the full file path in the minibuffer."
  (interactive)
  (message (buffer-file-name)))

;; make frame title contain the file path
(setq frame-title-format
    (list (format "%s %%S: %%j " (system-name))
        '(buffer-file-name "%f" (dired-directory dired-directory "%b"))))

;; make buffer names unique using path suffixes
(require 'uniquify)
(setq uniquify-buffer-name-style 'forward)

;; session save and restore
(desktop-save-mode 1)

;; Automatically reload files modified by external program
(global-auto-revert-mode 1)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(column-number-mode t)
 '(cua-mode t nil (cua-base))
 '(current-language-environment "UTF-8")
 '(save-place t nil (saveplace))
 '(show-paren-mode t))

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

;; (add-to-list 'load-path "~/github/emacs-hcl-mode/")
;; (require 'hcl-mode)
;; (add-to-list 'load-path "~/github/terraform-mode/")
;; (require 'terraform-mode)
;; (add-to-list 'load-path "~/github/yaml-mode/")
;; (require 'yaml-mode)
;; (add-to-list 'auto-mode-alist '("\\.yml\\'" . yaml-mode))

;; Tell emacs where is your personal elisp lib dir
;; (add-to-list 'load-path "~/.emacs.d/lisp/")
;; load the packaged named xyz.
;; (load "php-mode")

;; disable auto-indent
(when (fboundp 'electric-indent-mode) (electric-indent-mode -1))

;; indent using spaces instead of tabs
(setq-default indent-tabs-mode nil)

;; tab width
(setq tab-width 4)

;; scroll one line at a time
;; (setq mouse-wheel-scroll-amount '(1 ((shift) . 1)))
;; don't accelerate scrolling
(setq mouse-wheel-progressive-speed nil)

;; ;; delete trailing whitespace at the end of each line on save (all modes)
;; (add-hook 'before-save-hook 'delete-trailing-whitespace)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Menu
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; disable unused menu items
(define-key global-map [menu-bar tools browse-web] nil)
(define-key global-map [menu-bar tools calc] nil)
(define-key global-map [menu-bar tools calendar] nil)
(define-key global-map [menu-bar tools compose-mail] nil)
(define-key global-map [menu-bar tools directory-search] nil)
(define-key global-map [menu-bar tools games] nil)
(define-key global-map [menu-bar tools gnus] nil)
(define-key global-map [menu-bar tools rmail] nil)
(define-key global-map [menu-bar tools simple-calculator] nil)
(define-key global-map [menu-bar tools spell] nil)

;; add menu item: show file path
(define-key-after
    (lookup-key global-map [menu-bar file])
    [show-file-name]
    '("Show path" . show-file-name)
    'insert-file)

;; add menu item: delete window
(define-key-after
    (lookup-key global-map [menu-bar file])
    [delete-window]
    '("Delete window" . delete-window)
    'new-window-on-right)

;; add menu item: highlight occurences of the symbol at point
(define-key-after
    (lookup-key global-map [menu-bar edit])
    [highlight-symbol-at-point]
    '("Highlight occurences" . highlight-symbol-at-point)
    'mark-whole-buffer)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; LaTeX (AUCTeX)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; disable custom font for math in LaTeX mode
(setq font-latex-fontify-script nil)

;; Only change sectioning colour
(setq font-latex-fontify-sectioning 'color)
;; super-/sub-script on baseline
(setq font-latex-script-display (quote (nil)))
;; Do not change super-/sub-script font
(custom-set-faces
  '(font-latex-subscript-face ((t nil)))
  '(font-latex-superscript-face ((t nil)))
)
;; Exclude bold/italic from keywords
(setq font-latex-deactivated-keyword-classes
    '("italic-command" "bold-command" "italic-declaration" "bold-declaration"))
