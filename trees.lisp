;;; trees.lisp --- generic folding hierarchical list widget with
;;; indentation and headlines, a la orgmode

;; Copyright (C) 2011  David O'Toole

;; Author: David O'Toole <dto@gnu.org>
;; Keywords: 

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

(in-package :ioforms)

;;; Trees

(define-prototype tree (:parent "IOFORMS:LIST")
  (category :initform :structure)
  (top-level :initform nil)
  (temporary :initform t)
  action target (expanded :initform nil) (visible :initform t))

(define-method initialize tree 
    (&key action target top-level inputs pinned
	  expanded (label "blank tree item..."))
  (next%initialize self)
  (setf %action action
	%pinned pinned
	%expanded expanded
	%target target
	%top-level top-level
	%inputs inputs
	%label label)
  ;; become the parent
  (when inputs
    (dolist (each inputs)
      (pin each)
      (set-parent each self))))

(define-method evaluate tree ())

(define-method toggle-expanded tree ()
  (with-fields (expanded) self
    (setf expanded (if expanded nil t))
    (invalidate-layout self)))

(define-method is-expanded tree ()
  %expanded)

(define-method expand tree ()
  (setf %expanded t)
  (invalidate-layout self))

(define-method unexpand tree ()
  (setf %expanded nil)
  (invalidate-layout self))

(define-method click tree (x y)
  (declare (ignore x y))
  (with-fields (expanded action target) self
    (if (functionp action)
	(funcall action)
	(if (keywordp action)
	    (send action (or target 
			     ;; send to system if not specified.
			     ;; ...is this a good idea?
			     (symbol-value '*system*)))
	    ;; we're a subtree, not an individual tree command.
	    (toggle-expanded self)))))

(define-method display-string tree ()	    
  (with-fields (action label top-level) self
    (let ((ellipsis (concatenate 'string label *null-display-string*)))
      (if action
	  (etypecase action
	    (ioforms:object ellipsis)
	    ((or keyword function) label))
	  (if top-level label ellipsis)))))

(define-method layout-as-string tree (string)
  (with-fields (height width) self
    (setf height (dash 1 (font-height *block-font*)))
    (setf width 
	  (+ (dash 2) (font-text-extents string *block-font*)))))

(define-method layout tree ()
  (with-fields (expanded dash inputs label width) self
    (if expanded 
	;; we're an expanded subtree. lay it out
	(progn 
	  (setf dash 1)
	  (layout-as-list self)
	  (when label 
	    (setf width 
		  (max width 
		       (dash 4 (font-text-extents label *block-font*)))))
	  ;; make all inputs equally wide
	  (dolist (each inputs)
	    (setf (field-value :width each) (- width (dash 2)))))
	;; we're not expanded. just lay out for label.
	(layout-as-string self (display-string self)))))

(define-method header-height tree ()
  (font-height *block-font*))

(define-method header-width tree ()
  (if %expanded
      (dash 2 (font-text-extents (display-string self) *block-font*))
      %width))

(define-method hit tree (mouse-x mouse-y)
  (with-field-values (x y expanded inputs width height) self
    (when (within-extents mouse-x mouse-y x y (+ x width) (+ y height))
      (flet ((try (item)
	       (hit item mouse-x mouse-y)))
	(if (not expanded)
	    self
	    ;; we're expanded. is the mouse to the left of this
	    ;; tree's header tab thingy?
	    (if %top-level
		(when (and (< mouse-x (+ x (header-width self)))
			   (< (header-height self) mouse-y))
		  (some #'try inputs))
		(or (some #'try inputs) self)))))))
		
;;       (let ((hh (header-height self))
;; 	    (hw (header-width self)))
;; ;;	(message "HIT TREE")
;; 	(if (< y mouse-y (+ y hh))
;; 	    ;; we're even with the header text for this tree.
;; 	    ;; are we touching it?
;; 	    (if (< x mouse-x (+ x hw))
;; 		;; mouse is over tree title. return self to get event
;; 		;; we're in the corner (possibly over top of the text
;; 		;; of the next tree item's title in the tree bar). 
;; 		;; so, we close this tree.
;; 		(prog1 nil (unexpand self)))
;; 	    (labels ((try (it)
;; 		       (hit it mouse-x mouse-y)))
;; 	      (some #'try inputs)))))))

(define-method draw-hover tree ()
  nil)

(define-method draw-border tree ()
  nil)

(define-method draw-highlight tree ()
  (with-fields (y height expanded parent top-level) self
    (when parent
      (with-fields (x width) parent
	;; don't highlight top-level trees.
	(when (and (not expanded) (not top-level))
	  (draw-box x (+ y (dash 1)) width (+ height 1)
		  :color *highlight-background-color*)
	  (draw-label-string self (display-string self)))))))

(defparameter *tree-tab-color* "gray60")
(defparameter *tree-title-color* "white")

(define-method draw-expanded tree (&optional label)
  (with-field-values (action x y width height parent inputs top-level) self
    (let ((display-string (or label *null-display-string*))
	  (header (header-height self)))
      (if top-level
	  ;; draw the top of the treebar a bit differently to prevent 
	  ;; over-drawing other tree bar items.
	  (progn (draw-patch self
			     x
			     (dash 3 y)
			     (dash 2 x (header-width self))
			     (dash 1 y header)
			     :color *tree-tab-color*)
		 (draw-label-string self display-string *tree-title-color*)
		 ;; draw the rest of the tree background
		 (draw-patch self
			     x (dash 2 y header)
			     (dash 0 x width)
			     (- (dash 1 y height) (dash 1))))
	  (progn (draw-patch self x y (+ x width) (+ y height))
		 (draw-label-string self display-string)
		 (draw-line (+ x 1) (dash 2 y header) 
			    (+ x width -1) (dash 2 y header)
			    :color (find-color self :highlight))))
      ;; draw subtree items
      (dolist (each inputs)
	(draw each)))))
  
(define-method draw tree (&optional highlight)
  (with-fields (x y width height label action visible expanded) self
    (when visible
      (if expanded 
	  (draw-expanded self label)
	  ;; otherwise just draw tree name and highlight, if any
	  (draw-label-string self (display-string self))))))

;; see system.lisp for example tree menu
(defun make-tree (items &key target (tree-prototype "IOFORMS:TREE"))
  (labels ((xform (item)
	     (if (listp item)
		 (if (listp (first item))
		     (mapcar #'xform item)
		     (apply #'clone tree-prototype
			    :target target
			    (mapcar #'xform item)))
		 item)))
    (xform items)))

(defun make-menu (items &key target)
  (make-tree items :target target :tree-prototype "IOFORMS:MENU"))

;;; Menus

(define-prototype menu (:parent "IOFORMS:TREE")
  (category :initform :menu))

;; menu items should not accept any dragged widgets.
(define-method accept menu (&rest args) nil)

;;; A global menu bar

(defblock menubar :category :menu :temporary t)

(define-method initialize menubar (&optional menus)
  (apply #'next%initialize self 
	 (mapcar #'find-object menus))
  (with-fields (inputs) self
    (dolist (each inputs)
      (setf (field-value :top-level each) t)
      (pin each))))

(define-method hit menubar (mouse-x mouse-y)
  (with-fields (x y width height inputs) self
    (when (within-extents mouse-x mouse-y x y (+ x width) (+ y height))
      ;; are any of the menus open?
      (let ((opened-menu (find-if #'is-expanded inputs)))
	(labels ((try (m)
		   (when m (hit m mouse-x mouse-y))))
	  (let ((moused-menu (find-if #'try inputs)))
	    (if (and ;; moused-menu opened-menu
		     (object-eq moused-menu opened-menu))
		;; we're over the opened menu, let's check if 
		;; the user has moused onto the other parts of the menubar
	        (flet ((try-other (menu)
			 (when (not (object-eq menu opened-menu))
			   (try menu))))
		  (let ((other (some #'try-other inputs)))
		    ;; are we touching one of the other menubar items?
		    (if (null other)
			;; nope, just hit the opened submenu items.
			(try opened-menu)
			;; yes, switch menus.
			(prog1 other
			  (unexpand opened-menu)
			  (expand other)))))
		;; we're somewhere else. just try the main menus in
		;; the menubar.
		(let ((candidate (find-if #'try inputs)))
		  (if (null candidate)
		      ;; the user moused away. close the menus.
		      self
		      ;; we hit one of the other menus.
		      (if opened-menu
			  ;; there already was a menu open.
			  ;; close this one and open the new one.
			  (prog1 candidate
			    (unexpand opened-menu)
			    (expand candidate))
			  ;; no menu was open---just hit the menu headers
			  (some #'try inputs)))))))))))
			  		    	  
(define-method draw-border menubar () nil)

(define-method layout menubar ()
  (with-fields (x y width height inputs) self
    (setf x 0 y 0 width *screen-width* height (dash 1))
    (let ((x1 (dash 1)))
      (dolist (item inputs)
	(move-to item x1 y)
	(layout item)
	(incf x1 (dash 2 (header-width item)))
	(setf height (max height (field-value :height item)))))))
        
(define-method draw menubar ()
  (with-fields (x y width inputs) self
    (let ((bar-height (dash 2 1 (font-height *block-font*))))
      (draw-box x y 
		width bar-height
		:color (find-color self))
      (draw-line x bar-height width bar-height
		 :color (find-color self :shadow))
      (with-fields (inputs) self
	(dolist (each inputs)
	  (draw each))))))

(define-method close-menus menubar ()
  (with-fields (inputs) self
    (when (some #'is-expanded inputs)
      (mapc #'unexpand %inputs))))

;;; menus.lisp ends here
