;;; git.el --- An Elisp API for programmatically using Git

;; Copyright (C) 2013 Johan Andersson

;; Author: Johan Andersson <johan.rejeep@gmail.com>
;; Maintainer: Johan Andersson <johan.rejeep@gmail.com>
;; Version: 0.1.1
;; Keywords: git
;; URL: http://github.com/rejeep/git.el
;; Package-Requires: ((s "1.7.0") (dash "2.2.0") (f "0.10.0"))

;; This file is NOT part of GNU Emacs.

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;;; Code:

;; Todo: no-pager

(require 's)
(require 'dash)
(require 'f)

(defvar git-executable
  (executable-find "git")
  "Git executable.")

(defvar git-repo nil
  "Path to current working repo.")

(defvar git-args nil
  "List of args to include when running git command.")

(defconst git-stash-re "^\\(.+?\\): \\(?:WIP on\\|On\\) \\(.+\\): \\(.+\\)$"
  "Regular expression matching a stash.")

(put 'git-error 'error-conditions '(error git-error))
(put 'git-error 'error-message "GIT Error")

(defun git-error (string &rest args)
  "Signal a GIT error.

Signal an error with `git-error' type.

STRING is a `format' string, and ARGS are the formatted objects."
  (signal 'git-error (list (apply #'format string args))))

(defun git-run (command &rest args)
  "Run git COMMAND with ARGS."
  (let ((default-directory (if git-repo
			       (f-full git-repo)
			     (file-name-as-directory default-directory))))
    (with-temp-buffer
      (let ((exit-code
	     (apply
	      'call-process
	      (append
	       (list git-executable nil (current-buffer) nil)
	       (git--args command args)))))
	(if (zerop exit-code)
	    (buffer-string)
	  (git-error
	   "Error running command: %s %s\n%s"
	   git-executable
	   (s-join " " (git--args command args))
	   (buffer-string)))))))

(defun git-repo? (&optional directory) 
  "Return true if there is a git repo in DIRECTORY, false otherwise."
  (let ((default-directory (if directory
			       (f-full directory)
			     (file-name-as-directory default-directory))))
    (or
     (f-dir? (f-expand ".git"))
     (and
      (f-dir? (f-expand "info"))
      (f-dir? (f-expand "objects"))
      (f-dir? (f-expand "refs"))
      (f-file? (f-expand "HEAD"))))))

(defun git-ls-remote? (&optional repository)
  "Return `true' if it successfully talked with REPOSITORY.
If optional REPOSITORY is not set then use local repository path declared by `default-directory'."
  (let ((default-directory (file-name-as-directory default-directory)))
    (with-temp-buffer
      (let ((exit-code
	     (car
	      (list
	       (apply
		'call-process
		(append
		 (list git-executable nil (current-buffer) nil)
		 (git--args "ls-remote" "--exit-code" repository)))))))
	(when (zerop exit-code)
	  t)))))

(defun git-branch? (branch)
  "Return true if there's a branch called BRANCH."
  (-contains? (git-branches) branch))

(defun git-tag? (tag)
  "Return true if there's a tag called TAG."
  (-contains? (git-tags) tag))

(defun git-on-branch ()
  "Return currently active branch."
  (condition-case err
      (git--clean (git-run "rev-parse" "--abbrev-ref" "HEAD"))
    (git-error
     (git-error "Repository not initialized"))))

(defun git-on-branch? (branch)
  "Return true if BRANCH is currently active."
  (equal branch (git-on-branch)))

(defun git-add (&rest files)
  "Add FILES or everything."
  (git-run "add" (or files ".")))

(defun git-branch (branch)
  "Create BRANCH."
  (if (git-branch? branch)
      (git-error "Branch already exists %s" branch)
    (git-run "branch" branch)))

(defun git-branch-set-upstream (branch remote)
  "Set up BRANCH tracking information so REMOTE branch is considered BRANCH's upstream branch."
  (git-run "branch" (concat "--set-upstream-to=" remote "/" branch) branch))

(defun git-branches ()
  "List all available branches."
  (-map
   (lambda (line)
     (if (s-starts-with? "*" line)
         (substring line 2)
       line))
   (git--lines (git-run "branch"))))

(defun git-checkout (ref)
  "Checkout REF."
  (git-run "checkout" ref))

(defun git-clone (url &optional dir)
  "Clone URL to DIR (if present)."
  (git-run "clone" url dir))

(defun git-commit (message &rest files)
  "Commit FILES (or added files) with MESSAGE."
  (git-run "commit" "--allow-empty" "--allow-empty-message" (or files "-a") "--message" message files))

(defun git-fetch (&optional repo)
  "Fetch REPO."
  (git-run "fetch" repo))

(defun git-init (&optional dir bare)
  "Create new Git repo at DIR (or `git-repo').

If BARE is true, create a bare repo."
  (let ((git-repo (or dir git-repo)))
    (git-run "init" (and bare "--bare"))))

;; Todo: The solution used here is not bulletproof. For example if the
;; message contains a pipe, the :message will only include everything
;; before that pipe. Figure out a good solution for this.
(defun git-log (&optional branch)
  "Log history on BRANCH."
  (let ((logs (git--lines (git-run "log" "--format=%h|%an|%ae|%cn|%ce|%ad|%s"))))
    (-map
     (lambda (log)
       (let ((data (s-split "|" log)))
         (list
          :commit (nth 0 data)
          :author-name (nth 1 data)
          :author-email (nth 2 data)
          :comitter-name (nth 3 data)
          :comitter-email (nth 4 data)
          :date (nth 5 data)
          :message (nth 6 data))))
     logs)))

(defun git-config (option &optional value)
  "Set or get config OPTION.  Set to VALUE if present."
  (condition-case err
      (git--clean (git-run "config" option value))
    (git-error)))

(defun git-pull (&optional repo ref)
  "Set REPO and pull REF."
  (when (and repo ref)
      (git-run "pull" repo ref)))

(defun git-pull-all ()
  "Fetch all remotes."
  (git-run "pull" "--all"))


(defun git-push (&optional repo ref set-upstream)
  "Set REPO and update remote REF along with associated objects.
If SET-UPSTREAM is non-nil then add upstream reference."
  (git-run "push" (when set-upstream "-u") repo ref))

(defun git-remote? (name)
  "Return true if remote with NAME exists, false otherwise."
  (-contains? (git-remotes) name))

(defun git-remotes ()
  "Return list of all remotes."
  (git--lines (git-run "remote")))

(defun git-remote-add (name url &rest args)
  "Add remote with NAME and URL and ARGS."
  (git-run "remote" "add" args name url))

(defun git-remote-remove (name)
  "Remove remote with NAME."
  (if (git-remote? name)
      (git-run "remote" "remove" name)
    (git-error "No such remote %s" name)))

(defun git-reset (&optional commit mode)
  "Reset to COMMIT with MODE."
  (git-run "reset" (if mode (concat "--" (symbol-name mode))) commit))

(defun git-rm (path &optional recursive)
  "Remove PATH.

To remove directory, use RECURSIVE argument."
  (git-run "rm" path (and recursive "-r")))

(defun git-stash (&optional message)
  "Stash changes in a dirty tree with MESSAGE.

If a stash was created, the name of the stash is returned,
otherwise nil is returned."
  (let ((before-stashes (git-stashes)) after-stashes)
    (git-run "stash" "save" message)
    (setq after-stashes (git-stashes))
    (if (> (length after-stashes) (length before-stashes))
        (plist-get (car after-stashes) :name))))

(defun git-stashes ()
  "Return list of stashes."
  (let ((stashes (git--lines (git-run "stash" "list"))))
    (-map
     (lambda (stash)
       (let ((matches (s-match git-stash-re stash)))
         (list :name (nth 1 matches)
               :branch (nth 2 matches)
               :message (nth 3 matches))))
     stashes)))

(defun git-stash-pop (&optional name)
  "Apply and remove stash with NAME (or first stash)."
  (git-run "stash" "pop" name))

(defun git-stash-apply (&optional name)
  "Apply and keep stash with NAME (or first stash)."
  (git-run "stash" "apply" name))

(defun git-tag (tag)
  "Create TAG."
  (if (git-tag? tag)
      (git-error "Tag already exists %s" tag)
    (git-run "tag" tag)))

(defun git-tags ()
  "Return list of all tags."
  (git--lines (git-run "tag")))

(defun git-untracked-files ()
  "Return list of untracked files."
  (git--lines
   (git-run "ls-files" "--other" "--exclude-standard")))

(defun git-staged-files ()
  "Return list of staged files."
  (git--lines
   (git-run "diff" "--cached" "--name-only")))


;;;; Helpers

(defun git--lines (string)
  "Return list from STRING."
  (-reject 's-blank? (-map 's-trim (s-lines string))))

(defun git--clean (string)
  "Clean and trim STRING."
  (s-presence (s-trim string)))

(defun git--args (command &rest args)
  "Return COMMAND and list of ARGS."
  (-flatten (-reject 'null (append (list "--no-pager" command) args git-args))))


(provide 'git)

;;; git.el ends here
