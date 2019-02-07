;; make frame title contain the file path
(setq frame-title-format
    (list (format "%s %%S: %%j " (system-name))
        '(buffer-file-name "%f" (dired-directory dired-directory "%b"))))

;; make buffer names unique using path suffixes
(require 'uniquify)
(setq uniquify-buffer-name-style 'forward)

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

;; Tell emacs where is your personal elisp lib dir
(add-to-list 'load-path "~/.emacs.d/lisp/")

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

;; delete trailing whitespace at the end of each line on save (all modes)
(add-hook 'before-save-hook 'delete-trailing-whitespace)

