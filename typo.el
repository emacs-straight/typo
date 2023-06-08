;;; typo.el --- Completion style using typo analysis -*- lexical-binding: t -*-

;; Copyright (C) 2021, 2022, 2023  Free Software Foundation, Inc.

;; Author: Philip Kaludercic <philipk@posteo.net>
;; Maintainer: Philip Kaludercic <~pkal/public-inbox@lists.sr.ht>
;; URL: https://git.sr.ht/~pkal/typo/
;; Version: 1.0.1
;; Package-Requires: ((emacs "27.1"))
;; Keywords: convenience

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

;;; Commentary:

;; Typo.el implements a Norvig-Style[0] spell-corrector for Emacs'
;; completion system.
;;
;; To initialize this completion style, evaluate
;;
;;    (add-to-list 'completion-styles 'typo t)
;;
;; or configure the corresponding code in your initialisation file.
;;
;; [0] https://norvig.com/spell-correct.html

;;; Code:

(eval-when-compile (require 'inline))

(defgroup typo nil
  "Completion style using typo analysis."
  :group 'minibuffer)

(defcustom typo-level #'sqrt
  "Number of edits from the current word to a completion.
Optionally this option may also be a function, that takes a
number (indicating the length of the input) and returns a number
indicating the maximal number of permitted typos."
  :type '(choice function natnum))

(defcustom typo-shrink 1
  "Number of characters a word may shrink.
Any candidate that would shorted the word by more characters than
the value of this variable are rejected."
  :type 'natnum)

(defcustom typo-expand 4
  "Number of characters a word may expand.
Any candidate that would lengthen the word by more characters
than the value of this variable are rejected."
  :type 'natnum)

(defcustom typo-support-all-completions t
  "Non-nil means enable support for `all-completions'.
When enabled typo-based completion will also be applied to the
*Completions* buffer (or analogous concepts in other completion
frameworks)."
  :type 'boolean)

(define-inline typo--test (word key)
  (inline-letevals (word key)
    (inline-quote
     (let* ((len-word (length ,word))
	    (len-key (length ,key))
	    (typo-level
	     (cond
	      ((functionp typo-level)
	       (ceiling (funcall typo-level len-word)))
	      ((natnump typo-level)
	       typo-level)
	      ((error "Invalid `typo-level' %S" typo-level)))))
       (and (<= (- len-word len-key) typo-shrink)
            (<= (- len-key len-word) typo-expand)
	    (<= (string-distance ,word ,key)
		typo-level))))))

(defun typo-edits (word collection pred)
  "Generate a list of all multi-edit typos of WORD.
Only words that are in the COLLECTION and satisfy PRED will be
returned.  The variable `typo-level' specifies how many
single-letter typos are searched."
  (let (new-words)
    (cond
     ((functionp collection)
      (typo-edits word (funcall collection "" pred t) pred))
     ((and (listp collection) (consp (car collection))) ;alist
      (dolist (entry collection new-words)
	(let ((key (car entry)))
	  (when (symbolp key)
	    (setq key (symbol-name key)))
	  (when (typo--test word key)
	    (push key new-words)))))
     ((listp collection)		;regular list
      (dolist (entry collection new-words)
	(when (typo--test word entry)
	  (push entry new-words))))
     ((hash-table-p collection)
      (maphash
       (lambda (key _freq)
	 (when (typo--test word key)
	   (push key new-words)))
       collection)
      new-words)
     ((obarrayp collection)
      (mapatoms
       (lambda (atom)
	 (setq atom (symbol-name atom))
	 (when (typo--test word atom)
	   (push atom new-words)))
       collection)
      new-words))))

;;;###autoload
(defun typo-all-completions (string collection pred _point)
  "Generate all  versions of the STRING using COLLECTION.
COLLECTION and PRED are as defined in `all-completions'."
  (and typo-support-all-completions
       (typo-edits string collection pred)))

;;;###autoload
(defun typo-try-completion (string collection pred _point &optional _metadata)
  "Generate the most probable version of STRING using COLLECTION.
COLLECTION and PRED are as defined in `try-completion'."
  (let* ((result (typo-edits string collection pred))
	 (best (car result)))
    (dolist (other (cdr result))
      (when (< (string-distance string other)
	       (string-distance string best))
	(setq best other)))
    (and best (cons best (length best)))))

;;;###autoload
(add-to-list 'completion-styles-alist
             '(typo typo-try-completion typo-all-completions
	       "Typo-Fixing completion
I.e. when completing \"foobor\", with \"foobar\" in the
completion table, this style would attempt replace it with
\"foobar\", because the two strings are close by."))

(provide 'typo)

;;; typo.el ends here
