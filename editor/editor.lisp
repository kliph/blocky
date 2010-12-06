;;; editor.lisp --- IOSKETCH dev module

;; Copyright (C) 2010  David O'Toole

;; Author: David O'Toole <dto@gnu.org>
;; Keywords: games

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

(defpackage :editor
  (:use :iosketch :common-lisp)
  (:export editor))

(in-package :editor)

(setf iosketch:*dt* 20)
(setf iosketch:*resizable* t)

;;; Main program. 

(defparameter *window-width* 1200)
(defparameter *window-height* 720)
(defparameter *prompt-height* 20)
(defparameter *quickhelp-height* 100)
(defparameter *quickhelp-width* 390)
(defparameter *quickhelp-spacer* 0)
(defparameter *terminal-height* 100)
(defparameter *pager-height* 20)
(defparameter *sidebar-width* 400)

(defvar *form*)
(defvar *terminal*)
(defvar *prompt*)
(defvar *pager*)
(defvar *forms*)

(defun handle-editor-command (command)
  (assert (stringp command))
  (/insert *prompt* command)
  (/execute *prompt*))

(defvar *command-handler-function* #'handle-editor-command)

(define-prototype editor-prompt (:parent iosketch:=prompt=))

(define-method say editor-prompt (&rest args)
  (apply #'send nil :say *terminal* args))

(define-method goto editor-prompt ()
  (/unfocus (/left-form *forms*))
  (/unfocus (/right-form *forms*))
  (setf <mode> :direct))

(define-method do-after-execute editor-prompt ()
  (/clear-line self)  
  (setf <mode> :forward))

(define-method exit editor-prompt ()
  (/parent>>exit self)
  (/refocus *forms*))

;;; The frame where everything is displayed

(define-prototype frame (:parent iosketch:=stack=))

(defparameter *qwerty-keybindings*
  '(;; arrow key cursor movement
    ("UP" nil :move-cursor-up)
    ("DOWN" nil :move-cursor-down)
    ("LEFT" nil :move-cursor-left)
    ("RIGHT" nil :move-cursor-right)
    ;; emacs-style cursor movement
    ("A" (:control) :move-beginning-of-line)
    ("E" (:control) :move-end-of-line)
    ("F" (:control) :move-cursor-right)
    ("B" (:control) :move-cursor-left)
    ;; editing keys
    ("HOME" nil :move-beginning-of-line)
    ("END" nil :move-end-of-line)
    ("PAGEUP" nil :move-beginning-of-column)
    ("PAGEDOWN" nil :move-end-of-column)
    ;; switching windows
    ("TAB" nil :switch-panes)
    ("TAB" (:control) :switch-panes)
    ("LEFT" (:control) :left-pane)
    ("RIGHT" (:control) :right-pane)
    ;; dropping commonly-used cells
    ("1" (:control) :drop-data-cell)
    ("2" (:control) :drop-command-cell)
    ;; performing operations like clone, erase
    ("UP" (:control) :apply-right)
    ("DOWN" (:control) :apply-left)
    ("LEFTBRACKET" nil :apply-left)
    ("RIGHTBRACKET" nil :apply-right)
    ;; marking and stuff
    ("SPACE" (:control) :set-mark)
    ("SPACE" (:alt) :clear-mark)
    ("SPACE" (:meta) :clear-mark)
    ;; numeric keypad
    ("KP8" nil :move-cursor-up)
    ("KP2" nil :move-cursor-down)
    ("KP4" nil :move-cursor-left)
    ("KP6" nil :move-cursor-right)
    ("KP8" (:control) :apply-right)
    ("KP2" (:control) :apply-left)
    ("KP4" (:control) :left-pane)
    ("KP6" (:control) :right-pane)
    ;; entering data and confirm/cancel
    ("RETURN" nil :enter)
    ("RETURN" (:control) :exit) ;; see also handle-key
    ("ESCAPE" nil :cancel)
    ("G" (:control) :cancel)
    ;; view mode
    ("F9" nil :tile-view)
    ("F10" nil :label-view)
    ;; other
    ("X" (:control) :goto-prompt)
    ("X" (:alt) :goto-prompt)
    ("X" (:meta) :goto-prompt)
    ("T" (:control) :next-tool)))

(define-method install-keybindings frame ()
  (dolist (binding (case *user-keyboard-layout*
		     (:qwerty *qwerty-keybindings*)
		     (otherwise *qwerty-keybindings*)))
    (/generic-keybind self binding)))

(define-method palette-pane frame ()
  (nth 0 <children>))

(define-method script-pane frame ()
  (nth 1 <children>))

(define-method world-pane frame ()
  (nth 2 <children>))

(define-method other-pane frame ()
  (ecase <focus>
    (0 (/script-pane self))
    (1 (/world-pane self))
    (2 (/palette-pane self))))

(define-method selected-pane frame ()
  (nth <focus> <children>))

(define-method switch-panes frame ()
  (let ((newpos (mod (1+ <focus>) (length <children>))))
    (setf <focus> newpos)
    (ecase newpos
      (0 (/palette-pane self))
      (1 (/script-pane self))
      (2 (/world-page self)))))

(define-method paste frame (&optional page)
  (let ((source (if page 
		    (find-page page)
		    (field-value :world (/other-form self))))
	(destination (field-value :world (/selected-form self))))
    (multiple-value-bind (top left bottom right) (/mark-region (/selected-form self))
      (multiple-value-bind (top0 left0 bottom0 right0) (/mark-region (/other-form self))
	(let ((source-height (field-value :height source))
	      (source-width (field-value :width source)))
	  (with-fields (cursor-row cursor-column) (/selected-form self)
	    (let* ((height (or (when top (- bottom top))
			       (when top0 (- bottom0 top0))
			       source-height))
		   (width (or (when left (- right left))
			      (when left0 (- right0 left0))
			      source-width))
		   (r0 (or top cursor-row))
		   (c0 (or left cursor-column))
		   (r1 (or bottom (- height 1)))
		   (c1 (or right (- width 1)))
		   (sr (or top0 0))
		   (sc (or left0 0)))
	      (/paste-region destination source r0 c0 sr sc height width))))))))
  
(define-method commands frame ()
  "Syntax: command-name arg1 arg2 ...
Available commands: HELP EVAL SWITCH-PANES LEFT-PANE RIGHT-PANE
NEXT-TOOL SET-TOOL APPLY-LEFT APPLY-RIGHT VISIT SELECT SAVE-ALL
SAVE-MODULE LOAD-MODULE TILE-VIEW LABEL-VIEW QUIT VISIT APPLY-TOOL
CLONE ERASE CREATE-WORLD PASTE QUIT ENTER EXIT"
 nil)

(defun editor ()
  (setf iosketch:*screen-width* *window-width*)
  (setf iosketch:*screen-height* *window-height*)
  (iosketch:message "Initializing EDITOR...")
  (setf iosketch:*window-title* "EDITOR")
  (clon:initialize)
  (iosketch:set-screen-height *window-height*)
  (iosketch:set-screen-width *window-width*)
  (let* ((prompt (clone =editor-prompt=))
	 (help (clone =help-textbox=))
	 (help-prompt (clone =help-prompt=))
	 (quickhelp (clone =formatter=))
	 (form (clone =form=))
	 (form2 (clone =form= "*scratch*"))
	 (terminal (clone =narrator=))
	 (split (clone =frame=))
	 (stack (clone =stack=)))
    ;;
    (setf *form* form)
    (setf *prompt* prompt)
    (setf *terminal* terminal)
    (setf *forms* split)
    (labels ((resize-widgets ()
	       (/say terminal "Resizing to ~S" (list :width *screen-width* :height *screen-height*))
	       (/resize prompt :height *prompt-height* :width *screen-width*)
	       (/resize form :height (- *screen-height* *terminal-height* 
				       *prompt-height* *pager-height*) 
		       :width (- *screen-width* *sidebar-width* 2))
	       (/resize form2 :height (- *screen-height* *terminal-height* *prompt-height* *pager-height*) :width (- *sidebar-width* 2))
	       (/resize-to-scroll help :height (- *screen-height* *pager-height*) :width *screen-width*)
	       (/resize stack :width *screen-width* :height (- *screen-height* *pager-height* *prompt-height*))
	       (/resize split :width (- *screen-width* 1) :height (- *screen-height* *pager-height* *prompt-height* *terminal-height*))
	       (/resize terminal :height *terminal-height* :width *screen-width*)
	       (/resize quickhelp :height *quickhelp-height* :width *quickhelp-width*)
	       (/move quickhelp :y (- *screen-height* *quickhelp-height* *pager-height*) :x (- *screen-width* *quickhelp-width* *quickhelp-spacer*))
	       (/auto-position *pager*)))
      (add-hook 'iosketch:*resize-hook* #'resize-widgets))
    ;;
    (/resize prompt :height *prompt-height* :width *screen-width*)
    (/move prompt :x 0 :y 0)
    (/show prompt)
    (/install-keybindings prompt)
    (/install-keybindings split)
    (/say prompt "Welcome to EDITOR. Press ALT-X to enter command mode, or F1 for help.")
    (/set-mode prompt :forward) ;; don't start with prompt on
    (/set-receiver prompt split)
    ;; 
    (/resize form :height (- *screen-height* *terminal-height* 
			    *prompt-height* *pager-height*) 
	    :width (- *screen-width* *sidebar-width*))
    (/move form :x 0 :y 0)
    (/set-prompt form prompt)
    (/set-narrator form terminal)
    ;;
    (/resize-to-scroll help :height (- *screen-height* *pager-height*) :width *screen-width*)
    (/move help :x 0 :y 0)
    (setf (field-value :read-only help) t)
    (let ((text	(find-resource-object "editor-help-message")))
      (/set-buffer help text))
    ;;
    (/resize help-prompt :width 10 :height 10)
    (/move help-prompt :x 0 :y 0)
    (/hide help-prompt)
    (/set-receiver help-prompt help)

    ;;
    (/resize form2 :height (- *screen-height* *terminal-height* *prompt-height* *pager-height*) :width *sidebar-width*)
    (/move form2 :x 0 :y 0)
    (setf (field-value :header-style form2) nil)
    (/set-prompt form2 prompt)
    (/set-narrator form2 terminal)
    ;;
    (iosketch:halt-music 1000)
    ;;
    ;; (/resize help :height 540 :width 800) 
    ;; (/move help :x 0 :y 0)
    (/resize-to-scroll help :height 540 :width 800) 
    (/move help :x 0 :y 0)
    (let ((text	(find-resource-object "editor-help-message")))
      (/set-buffer help text))
    ;;
    (/resize quickhelp :height *quickhelp-height* :width *quickhelp-width*)
    (/move quickhelp :y (- *screen-height* *quickhelp-height* *pager-height*) :x (- *screen-width* *quickhelp-width* *quickhelp-spacer*))
    (let ((text	(find-resource-object "editor-quickhelp-message")))
      (dolist (line text)
    	(dolist (string line)
    	  (funcall #'send nil :print-formatted-string quickhelp string))
    	(/newline quickhelp)))
    ;;
    (/resize stack :width *screen-width* :height (- *screen-height* *pager-height* *prompt-height*))
    (/move stack :x 0 :y 0)
    (/set-children stack (list split terminal prompt))
    ;;
    (/resize split :width *screen-width* :height (- *screen-height* *pager-height* *terminal-height* *prompt-height*))
    (/move split :x 0 :y 0)
    (/set-children split (list form form2))
    ;;
    (/resize terminal :height *terminal-height* :width *screen-width*)
    (/move terminal :x 0 :y (- *screen-height* *terminal-height*))
    (/set-verbosity terminal 0)
    ;;
    ;;
    (setf *pager* (clone =pager=))
    (/auto-position *pager*)
    ;;
    (/add-page *pager* :edit (list prompt stack split terminal quickhelp))
    (/add-page *pager* :help (list help-prompt help))
    (/select *pager* :edit)
    (iosketch:enable-classic-key-repeat 100 100)
    (in-package :iosketch)
    (/focus-left *forms*)
;;    (run-hook 'iosketch:*resize-hook*)
))

(editor)

;;; editor.lisp ends here
