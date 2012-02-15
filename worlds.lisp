;; worlds.lisp --- places where gameplay happens

;; Copyright (C) 2006, 2007, 2008, 2009, 2010, 2011  David O'Toole

;; Author: David O'Toole %dto@ioforms.org
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
;; along with this program.  If not, see %http://www.gnu.org/licenses/

(in-package :blocky)

(define-block world
  (variables :initform nil 
	     :documentation "Hash table mapping values to values, local to the current world.")
  (player :documentation "The player cell (or object).")
  (background :initform nil)
  (background-color :initform "black")
  (x :initform 0)
  (y :initform 0)
  (heading :initform 0.0)
  (height :initform 16)
  (width :initform 16)
  ;; objects and collisions
  (objects :initform nil :documentation "A hash table with all the world's object.")
  (quadtree :initform nil)
  (quadtree-depth :initform nil)
  ;; viewing window
  (window-x :initform 0)
  (window-y :initform 0)
  (window-x0 :initform nil)
  (window-y0 :initform nil)
  (window-scrolling-speed :initform 2)
  (window-scale-x :initform 1)
  (window-scale-y :initform 1))

(defmacro define-world (name &body body)
  `(define-block (,name :super "BLOCKY:WORLD")
     ,@body))

(define-method get-objects world ()
  (loop for object being the hash-keys in %objects collect object))

(define-method layout world ())

;; Defining and scrolling the screen viewing window

(define-method window-bounding-box world ()
  (values %window-y 
	  %window-x
	  (+ %window-x *gl-screen-width*)
	  (+ %window-y *gl-screen-height*)))

(define-method move-window-to world (x y)
  (setf %window-x x 
	%window-y y))

(define-method move-window world (dx dy)
  (incf %window-x dx)
  (incf %window-y dy))

(define-method glide-window-to world (x y)
  (setf %window-x0 x)
  (setf %window-y0 y))

(define-method glide-window-to-object world (object)
  (multiple-value-bind (top left right bottom) 
      (bounding-box object)
    (declare (ignore right bottom))
    (glide-window-to 
     self 
     (max 0 (- left (/ *gl-screen-width* 2)))
     (max 0 (- top (/ *gl-screen-width* 2))))))

(define-method glide-follow world (object)
  (with-fields (window-x window-y width height) self
    (let ((margin-x (* 1/3 *gl-screen-width*))
	  (margin-y (* 1/3 *gl-screen-height*))
	  (object-x (field-value :x object))
	  (object-y (field-value :y object)))
    ;; are we outside the "comfort zone"?
    (if (or 
	 ;; too far left
	 (> (+ window-x margin-x) 
	    object-x)
	 ;; too far right
	 (> object-x
	    (- (+ window-x *gl-screen-width*)
	       margin-x))
	 ;; too far up
	 (> (+ window-y margin-y) 
	    object-y)
	 ;; too far down 
	 (> object-y 
	    (- (+ window-y *gl-screen-height*)
	       margin-y)))
	;; yes. recenter.
	(glide-window-to self
			 (max 0
			      (min (- width *gl-screen-width*)
				   (- object-x 
				      (truncate (/ *gl-screen-width* 2)))))
			 (max 0 
			      (min (- height *gl-screen-height*)
				   (- object-y 
				      (truncate (/ *gl-screen-height* 2))))))))))

(define-method update-window-glide world ()
  (with-fields (window-x window-x0 window-y window-y0 window-scrolling-speed) self
    (labels ((nearby (a b)
	       (> window-scrolling-speed (abs (- a b))))
	     (jump (a b)
	       (if (< a b) window-scrolling-speed (- window-scrolling-speed))))
      (when (and window-x0 window-y0)
	(if (nearby window-x window-x0)
	    (setf window-x0 nil)
	    (incf window-x (jump window-x window-x0)))
	(if (nearby window-y window-y0)
	    (setf window-y0 nil)
	    (incf window-y (jump window-y window-y0)))))))

(define-method scale-window world (&optional (window-scale-x 1.0) (window-scale-y 1.0))
  (setf %window-scale-x window-scale-x)
  (setf %window-scale-y window-scale-y))

(define-method project world ()
  (do-orthographic-projection)
  (do-window %window-x %window-y %window-scale-x %window-scale-y))

(define-method is-empty world ()
  (or (null %objects)
      (zerop (hash-table-count %objects))))

(define-method initialize world ()
  (setf %variables (make-hash-table :test 'equal))
  (setf %objects (make-hash-table :test 'equal)))
  
(define-method handle-event world (event)
  (or (handle-event%%block self event)
      (with-fields (player quadtree) self
	(when player 
	  (prog1 t
	    (let ((*quadtree* quadtree))
	      (handle-event player event)))))))

;;; The object layer. 

(define-method grab-focus world ())

(define-method add-block world (object &optional x y append)
  (with-fields (quadtree) self
    (let ((*quadtree* quadtree))
      (assert (not (gethash (find-uuid object) 
			    %objects)))
      (setf (gethash (find-uuid object)
		     %objects)
	    t)
      (when (and (numberp x) (numberp y))
	(setf (field-value :x object) x
	      (field-value :y object) y))
      (clear-saved-location object)
      (when quadtree
	(quadtree-insert quadtree object)))))

(define-method drop-block world (block x y)
  (add-block self block)
  (move-to block x y))
      
(define-method remove-block world (object)
  (remhash (find-uuid object) %objects)
  (when (field-value :quadtree-node object)
    (quadtree-delete %quadtree object)))

(define-method discard-block world (object)
  (remhash (find-uuid object) %objects))

;;; World-local variables

(define-method setvar world (var value)
  (setf (gethash var %variables) value))

(define-method getvar world (var)
  (gethash var %variables))

(defun world-variable (var-name)
  (getvar *world* var-name))

(defun set-world-variable (var-name value)
  (setvar *world* var-name value))

(defsetf world-variable set-world-variable)

(defmacro with-world-variables (vars &rest body)
  (labels ((make-clause (sym)
	     `(,sym (world-variable ,(make-keyword sym)))))
    (let* ((symbols (mapcar #'make-non-keyword vars))
	   (clauses (mapcar #'make-clause symbols)))
      `(symbol-macrolet ,clauses ,@body))))

;;; About the player
			        
(define-method get-player world ()
  %player)

(defun player ()
  (get-player *world*))

(define-method set-player world (player)
  "Set PLAYER as the player object to which the World will forward
most user command messages. (See also the method `forward'.)"
  (setf %player player)
  (add-block self player))

;;; Configuring the world's space and its quadtrees

(defparameter *world-bounding-box-scale* 1.01)

;; see also quadtree.lisp 

(define-method install-quadtree world ()
  (unless (is-empty self)
    ;; make a box with a one-percent margin on all sides.
    ;; this margin helps edge objects not pile up in quadrants
    (let ((box (multiple-value-list
		(scale-bounding-box 
		 (multiple-value-list (bounding-box self))
		 *world-bounding-box-scale*))))
      (destructuring-bind (top left right bottom) box
	(with-fields (quadtree) self
	  (setf quadtree (build-quadtree 
			  box 
			  (or %quadtree-depth 
			      *default-quadtree-depth*)))
	  (quadtree-fill quadtree (get-objects self)))))))

(define-method resize world (new-height new-width)
  (assert (and (plusp new-height)
	       (plusp new-width)))
  (with-fields (height width quadtree objects) self
    (setf height new-height)
    (setf width new-width)
    (when quadtree
      (install-quadtree self))))

(define-method shrink-wrap world ()
  (prog1 self
    (let ((objects (get-objects self)))
      (with-fields (quadtree height width) self
	;; adjust bounding box so that all objects have positive coordinates
	(multiple-value-bind (top left right bottom)
	    (find-bounding-box objects)
	  ;; move all the objects
	  (dolist (object objects)
	    (with-fields (x y) object
	      (move-to object (- x left) (- y top))))
	  ;; resize the world
	  (setf %x 0 %y 0)
	  (resize self (- bottom top) (- right left)))))))

;; Algebraic operations on worlds and their contents

(defvar *world-prototype* "BLOCKY:WORLD")

(defmacro with-world (world &rest body)
  `(let ((*world* ,world))
     (prog1 *world*
       ,@body)))

(defmacro with-world-prototype (world &rest body)
  `(let ((*world-prototype* (find-super ,world)))
     ,@body))

(define-method adjust-bounding-box-maybe world ()
  (if (is-empty self)
      self
      (let ((objects-bounding-box 
	      (multiple-value-list 
	       (find-bounding-box (get-objects self)))))
	(destructuring-bind (top left right bottom)
	    objects-bounding-box
	  ;; are all the objects inside the existing box?
	  (prog1 self
	    (unless (bounding-box-contains 
		     (multiple-value-list (bounding-box self))
		     objects-bounding-box)
	      (resize self bottom right)))))))

(defmacro with-new-world (&body body)
  `(with-world (clone *world-prototype*) 
     ,@body
     (adjust-bounding-box-maybe (world))))

(define-method paste world (other-world &optional (dx 0) (dy 0))
  (dolist (object (get-objects other-world))
    (with-fields (x y) object
      (clear-saved-location object)
      (add-block self object)
      (move-to object (+ x dx) (+ y dy)))))

(defun translate (world dx dy)
  (when world
    (assert (and (numberp dx) (numberp dy)))
    (with-new-world 
      (paste (world) world dx dy))))

(defun combine (world1 world2)
  (with-new-world 
    (when (and world1 world2)
      (dolist (object (nconc (get-objects world1)
			     (mapcar #'duplicate (get-objects world2))))
	(add-block (world) object)))))

(define-method scale world (sx &optional sy)
  (let ((objects (get-objects self)))
    (dolist (object objects)
      (with-fields (x y width height) object
	(move-to object (* x sx) (* y (or sy sx)))
	(resize object (* width sx) (* height (or sy sx))))))
  (shrink-wrap self))

(define-method destroy-region world (bounding-box))

(define-method copy world ()
  (with-new-world 
    (dolist (object (mapcar #'duplicate (get-objects self)))
      (add-block (world) object))))

(defun vertical-extent (world)
  (if (or (null world)
	  (is-empty world))
      0
      (multiple-value-bind (top left right bottom)
	  (bounding-box world)
	(declare (ignore left right))
	(- bottom top))))

(defun horizontal-extent (world)
  (if (or (null world)
	  (is-empty world))
      0
      (multiple-value-bind (top left right bottom)
	  (bounding-box world)
	(declare (ignore top bottom))
	(- right left))))
  
(defun arrange-below (&optional world1 world2)
  (when (and world1 world2)
    (combine world1
	     (translate world2
			0 
			(field-value :height world1)))))

(defun arrange-beside (&optional world1 world2)
  (when (and world1 world2)
    (combine world1 
	     (translate world2
			(field-value :width world1)
			0))))

(defun stack-vertically (&rest worlds)
  (reduce #'arrange-below worlds :initial-value (with-new-world)))

(defun stack-horizontally (&rest worlds)
  (reduce #'arrange-beside worlds :initial-value (with-new-world)))

(define-method flip-horizontally world ()
  (let ((objects (get-objects self)))
    (dolist (object objects)
      (with-fields (x y) object
	(move-to object (- x) y))))
  ;; get rid of negative coordinates
  (shrink-wrap self))

(define-method flip-vertically world ()
  (let ((objects (get-objects self)))
    (dolist (object objects)
      (with-fields (x y) object
	(move-to object x (- y)))))
  (shrink-wrap self))

(define-method mirror-horizontally world ()
  (stack-horizontally 
   self 
   (flip-horizontally (duplicate self))))

(define-method mirror-vertically world ()
  (stack-vertically 
   self 
   (flip-vertically (duplicate self))))

(defun with-border (border world)
  (with-fields (height width) world
    (with-new-world 
      (paste (world) world border border) 
      (resize (world)
	      (+ height (* border 2))
	      (+ width (* border 2))))))

;;; Draw the world

(define-method draw world ()
  ;; (declare (optimize (speed 3)))
  (let ((*world* self))
    (project self) ;; set up camera
    (with-field-values (objects quadtree width height background background-color) self
      ;; draw background 
      (if background
	  (draw-image background 0 0)
	  (when background-color
	    (draw-box 0 0 width height
		      :color background-color)))
      (let ((box (multiple-value-list (window-bounding-box self))))
	(loop for object being the hash-keys in objects do
	  ;; only draw onscreen objects
	  (colliding-with-bounding-box object box)
	  (draw object))))))
      ;; ;; draw all onscreen objects
      ;; (quadtree-map-collisions 
      ;;  quadtree 
      ;;  (multiple-value-list (window-bounding-box self))
      ;;  #'draw))))
  
;;; Simulation update

(define-method update world (&optional no-collisions)
  ;; (declare (optimize (speed 3)))
  ;; (declare (ignore args))
  (let ((*world* self))
    (with-field-values (quadtree objects height width player) self
      ;; build quadtree if needed
      (when (null quadtree)
      	(install-quadtree self))
      (let ((*quadtree* %quadtree))
	(assert (zerop *quadtree-depth*))
	;; run the objects
	(loop for object being the hash-keys in %objects do
	  (update object)
	  (run-tasks object))
	;; update window movement
	(glide-follow self player)
	(update-window-glide self)
	;; detect collisions
	(unless no-collisions
	  (loop for object being the hash-keys in objects do
	    (unless (eq :passive (field-value :collision-type object))
	      (quadtree-collide *quadtree* object))))))))

;;; worlds.lisp ends here
