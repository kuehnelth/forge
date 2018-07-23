;;; forge-commands.el --- forge commands          -*- lexical-binding: t -*-

;; Copyright (C) 2018  Jonas Bernoulli

;; Author: Jonas Bernoulli <jonas@bernoul.li>
;; Maintainer: Jonas Bernoulli <jonas@bernoul.li>

;; Magit is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; Magit is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Magit.  If not, see http://www.gnu.org/licenses.

;;; Code:

(require 'forge)

;;; Popup

;;;###autoload (autoload 'forge-popup "forge-commands" nil t)
(magit-define-popup forge-popup
  "Popup console for forge commands."
  nil nil nil
  :actions '((?f "Fetch forge"         forge-pull)
             (?p "Create pull-request" forge-create-pullreq)
             (?i "Create issue"        forge-create-issue)
             (?P "List pull-requests"  forge-list-pullreqs)
             (?I "List issues"         forge-list-issues))
  :max-action-columns 1)

;;; Pull

;;;###autoload
(defun forge-pull (&optional repo)
  "Pull topics from the forge repository."
  (interactive)
  (unless repo
    (setq repo (forge-get-repository t)))
  (with-slots (owner name) repo
    (message "Pulling forge repository %s/%s..." owner name)
    (forge--pull repo)
    (oset repo sparse-p nil)
    (when-let ((remote  (oref repo remote))
               (refspec (oref-default repo pullreq-refspec)))
      (unless (member refspec (magit-get-all "remote" remote "fetch"))
        (magit-call-git "config" "--add"
                        (format "remote.%s.fetch" remote)
                        refspec))
      (magit-git-fetch remote (magit-fetch-arguments)))))

(cl-defmethod forge--pull ((_repo forge-repository))) ; NOOP

;;;###autoload
(defun forge-pull-notifications ()
  (interactive)
  (pcase-dolist (`(,githost ,_ ,_ ,class) forge-alist)
    (forge--pull-notifications class githost)))

;;; Browse

;;;###autoload
(defun forge-browse-commit (rev)
  "Visit the url corresponding to REV using a browser."
  (interactive
   (list (or (magit-completing-read "Browse commit"
                                    (magit-list-branch-names)
                                    nil nil nil 'magit-revision-history
                                    (magit-branch-or-commit-at-point))
             (user-error "Nothing selected"))))
  (let* ((repo (forge-get-repository t))
         (remote (oref repo remote))
         (branches (magit-list-remote-branch-names remote))
         (available (-any-p (lambda (branch)
                              (magit-rev-ancestor-p rev branch))
                            branches)))
    (unless available
      (if-let ((branch (-some (lambda (branch)
                                (magit-rev-ancestor-p rev branch))
                              (cl-set-difference
                               (magit-list-remote-branch-names remote)
                               branches :test #'equal))))
          (setq repo (forge-get-repository
                      'stub (cdr (magit-split-branch-name branch))))
        (message "%s does not appear to be available on any remote.  %s"
                 rev "You might have to push it first.")))
    (browse-url
     (forge--format-url repo 'commit-url-format
                        `((?r . ,(magit-rev-verify-commit rev)))))))

;;;###autoload
(defun forge-browse-branch (branch)
  "Visit the url corresponding BRANCH using a browser."
  (interactive (list (magit-read-branch "Browse branch")))
  (let (remote)
    (if (magit-remote-branch-p branch)
        (let ((cons (magit-split-branch-name branch)))
          (setq remote (car cons))
          (setq branch (cdr cons)))
      (or (setq remote (or (magit-get-push-remote branch)
                           (magit-get-upstream-remote branch)))
          (user-error "Cannot determine remote for %s" branch)))
    (browse-url (forge--format-url remote 'branch-url-format
                                   `((?r . ,branch))))))

;;;###autoload
(defun forge-browse-remote (remote)
  "Visit the url corresponding to REMOTE using a browser."
  (interactive (list (magit-read-remote "Browse remote")))
  (browse-url (forge--format-url remote 'remote-url-format)))

;;;###autoload
(defun forge-browse-pullreqs (repo)
  "Visit the url corresponding to REPO's pull-requests using a browser."
  (interactive (list (forge-get-repository t)))
  (browse-url (forge--format-url repo 'pullreqs-url-format)))

;;;###autoload
(defun forge-browse-pullreq (pullreq)
  "Visit the url corresponding to PULLREQ using a browser."
  (interactive (list (forge-read-pullreq "Browse pull-request")))
  (browse-url (forge--format-url pullreq 'pullreq-url-format))
  (oset pullreq unread-p nil))

;;;###autoload
(defun forge-browse-issues (repo)
  "Visit the url corresponding to REPO's issues using a browser."
  (interactive (list (forge-get-repository t)))
  (browse-url (forge--format-url repo 'issues-url-format)))

;;;###autoload
(defun forge-browse-issue (issue)
  "Visit the url corresponding to ISSUE using a browser."
  (interactive (list (forge-read-issue "Browse issue")))
  (browse-url (forge--format-url issue 'issue-url-format))
  (oset issue unread-p nil))

;;;###autoload
(defun forge-browse-post ()
  "Visit the url corresponding to the post at point using a browser."
  (interactive)
  (let ((post (forge-post-at-point)))
    (cl-etypecase post
      (forge-issue   (forge-browse-issue post))
      (forge-pullreq (forge-browse-pullreq post))
      (forge-post
       (let ((topic (forge-get-topic post)))
         (browse-url
          (forge--format-url post
                             (cl-etypecase topic
                               (forge-issue   'issue-post-url-format)
                               (forge-pullreq 'pullreq-post-url-format))))
         (oset topic unread-p nil))))))

;;; Visit

;;;###autoload
(defun forge-visit-pullreq (pullreq)
  "View PULLREQ in a buffer."
  (interactive (list (forge-read-pullreq "View pull-request")))
  (let ((magit-generate-buffer-name-function 'forge-topic-buffer-name))
    (magit-mode-setup-internal #'forge-topic-mode (list pullreq) t))
  (oset pullreq unread-p nil))

;;;###autoload
(defun forge-visit-issue (issue)
  "View ISSUE in a buffer."
  (interactive (list (forge-read-issue "View issue")))
  (let ((magit-generate-buffer-name-function 'forge-topic-buffer-name))
    (magit-mode-setup-internal #'forge-topic-mode (list issue) t))
  (oset issue unread-p nil))

;;; Create

(defun forge-create-pullreq (source target)
  "Create a new pull-request."
  (interactive
   (let* ((atpoint  (magit-branch-at-point))
          (current  (magit-get-current-branch))
          (branches (magit-list-remote-branch-names))
          (source   (magit-completing-read
                     "Source branch" branches nil t nil 'magit-revision-history
                     (or (and atpoint
                              (if (magit-remote-branch-p atpoint)
                                  atpoint
                                (magit-get-push-branch atpoint t)))
                         (and current
                              (if (magit-remote-branch-p current)
                                  current
                                (magit-get-push-branch current t))))))
          (local    (cdr (magit-split-branch-name source)))
          (local    (and (magit-branch-p local) local))
          (upstream (and local (magit-get-upstream-branch local)))
          (branches (delete source branches))
          (target   (magit-completing-read
                     "Target branch" branches nil t nil 'magit-revision-history
                     (or (and upstream
                              (if (magit-remote-branch-p upstream)
                                  upstream
                                (magit-get-upstream-branch upstream)))
                         (car (member "origin/master" branches))))))
     (list source target)))
  (let ((buf (forge--prepare-post-buffer "new-pullreq")))
    (with-current-buffer buf
      (setq forge--buffer-base-branch target)
      (setq forge--buffer-head-branch source)
      (setq forge--buffer-post-object (forge-get-repository t))
      (setq forge--submit-post-function 'forge--submit-create-pullreq))
    (forge--display-post-buffer buf)))

(defun forge-create-issue ()
  "Create a new issue."
  (interactive)
  (let ((buf (forge--prepare-post-buffer "new-issue")))
    (with-current-buffer buf
      (setq forge--buffer-post-object (forge-get-repository t))
      (setq forge--submit-post-function 'forge--submit-create-issue))
    (forge--display-post-buffer buf)))

(defun forge-create-post ()
  "Create a new post on an existing topic."
  (interactive)
  (let* ((topic (car magit-refresh-args))
         (buf (forge--prepare-post-buffer
               (format "%s:new-comment" (oref topic number)))))
    (with-current-buffer buf
      (setq forge--buffer-post-object topic)
      (setq forge--submit-post-function 'forge--submit-create-post))
    (forge--display-post-buffer buf)))

;;; Edit

(defun forge-edit-post ()
  "Edit an existing post."
  (interactive)
  (let* ((post (forge-post-at-point))
         (buf (forge--prepare-post-buffer
               (cl-typecase post
                 (forge-topic (format "%s"
                                      (oref post number)))
                 (forge-post  (format "%s:%s"
                                      (oref (forge-get-topic post) number)
                                      (oref post number)))))))
    (with-current-buffer buf
      (setq forge--buffer-post-object post)
      (setq forge--submit-post-function 'forge--submit-edit-post)
      (erase-buffer)
      (when (cl-typep post 'forge-topic)
        (insert "# " (oref post title) "\n\n"))
      (insert (oref post body)))
    (forge--display-post-buffer buf)))

(defun forge-edit-topic-title (topic)
  "Edit the title of TOPIC."
  (interactive (list (forge-read-topic "Edit title of")))
  (forge--set-topic-title
   (forge-get-repository topic) topic
   (read-string "Title: " (oref topic title))))

(defun forge-edit-topic-labels (topic)
  "Edit the labels of TOPIC."
  (interactive (list (forge-read-topic "Edit labels of")))
  (let ((repo (forge-get-repository topic))
        (crm-separator ","))
    (forge--set-topic-labels
     repo topic (magit-completing-read-multiple*
                 "Labels: "
                 (mapcar #'cadr (oref repo labels))
                 nil t
                 (mapconcat #'car (closql--iref topic 'labels) ",")))))

(defun forge-edit-topic-assignees (topic)
  "Edit the assignees of TOPIC."
  (interactive (list (forge-read-topic "Edit assignees of")))
  (let ((repo (forge-get-repository topic))
        (crm-separator ","))
    (forge--set-topic-assignees
     repo topic (magit-completing-read-multiple*
                 "Assignees: "
                 (mapcar #'cadr (oref repo assignees))
                 nil t
                 (mapconcat #'car (closql--iref topic 'assignees) ",")))))

;;; Branch

;;;###autoload
(defun forge-branch-pullreq (pullreq)
  "Create and configure a new branch from a pull-request.
Please see the manual for more information."
  (interactive (list (forge-read-pullreq "* Branch pull request")))
  (with-slots (number title editable-p cross-repo-p
                      base-ref base-repo
                      head-ref head-repo head-user)
      pullreq
    (let* ((host (oref (forge-get-repository nil) githost))
           (upstream-url (format "git@%s:%s.git" host base-repo))
           (upstream (or (--first (forge--url-equal
                                   (magit-git-string "remote" "get-url" it)
                                   upstream-url)
                                  (magit-list-remotes))
                         (user-error
                          "Upstream repository %s not available as a remote"
                          upstream-url)))
           (upstream-url (magit-git-string "remote" "get-url" upstream))
           (remote head-user)
           (branch (forge--pullreq-branch pullreq t))
           (pr-branch head-ref))
      (if (not cross-repo-p)
          (let ((tracking (concat upstream "/" pr-branch)))
            (unless (magit-branch-p tracking)
              (magit-call-git "fetch" upstream))
            (let ((inhibit-magit-refresh t))
              (magit-branch branch tracking))
            (magit-set upstream "branch" branch "pushRemote")
            (magit-set upstream "branch" branch "pullRequestRemote"))
        (if (magit-remote-p remote)
            (let ((url   (magit-git-string "remote" "get-url" remote))
                  (fetch (magit-get-all "remote" remote "fetch")))
              (unless (forge--url-equal
                       url (format "git@%s:%s.git" host head-repo))
                (user-error
                 "Remote `%s' already exists but does not point to %s"
                 remote url))
              (unless (member (format "+refs/heads/*:refs/remotes/%s/*" remote)
                              fetch)
                (magit-git "remote" "set-branches" "--add" remote pr-branch)
                (magit-git "fetch" remote)))
          (magit-git
           "remote" "add" "-f" "--no-tags"
           "-t" pr-branch remote
           (cond ((or (string-prefix-p "git@" upstream-url)
                      (string-prefix-p "ssh://git@" upstream-url))
                  (format "git@%s:%s.git" host head-repo))
                 ((string-prefix-p "https://" upstream-url)
                  (format "https://%s/%s.git" host head-repo))
                 ((string-prefix-p "git://" upstream-url)
                  (format "git://%s/%s.git" host head-repo))
                 (t (error "%s has an unexpected format" upstream-url)))))
        (magit-git "branch" branch (concat remote "/" pr-branch))
        (if (and editable-p
                 (equal branch pr-branch))
            (magit-set remote "branch" branch "pushRemote")
          (magit-set upstream "branch" branch "pushRemote")))
      (magit-set remote "branch" branch "pullRequestRemote")
      (magit-set "true" "branch" branch "rebase")
      (magit-git "branch" branch
                 (concat "--set-upstream-to="
                         (if magit-branch-prefer-remote-upstream
                             (concat upstream "/" base-ref)
                           base-ref)))
      (magit-set (number-to-string number) "branch" branch "pullRequest")
      (magit-set title                     "branch" branch "description")
      (magit-refresh)
      branch)))

;;;###autoload
(defun forge-checkout-pullreq (pullreq)
  "Create, configure and checkout a new branch from a pull-request.
Please see the manual for more information."
  (interactive (list (forge-read-pullreq "Checkout pull request")))
  (magit-checkout
   (let ((inhibit-magit-refresh t))
     (forge-branch-pullreq pullreq))))

;;;###autoload
(defun forge-checkout-worktree (path pullreq)
  "Create, configure and checkout a new worktree from a pull-request.
This is like `magit-checkout-pull-request', except that it
also creates a new worktree. Please see the manual for more
information."
  (interactive
   (let ((pullreq (forge-read-pullreq "Checkout pull request")))
     (with-slots (number head-ref) pullreq
       (let ((path (let ((branch (forge--pullreq-branch pullreq t)))
                     (read-directory-name
                      (format "Checkout #%s as `%s' in new worktree: "
                              number branch)
                      (file-name-directory
                       (directory-file-name default-directory))
                      nil nil
                      (if (string-match-p "\\`pr-[0-9]+\\'" branch)
                          (number-to-string number)
                        (format "%s-%s" number head-ref))))))
         (when (equal path "")
           (user-error "The empty string isn't a valid path"))
         (list path pullreq)))))
  (when (and (file-exists-p path)
             (not (and (file-directory-p path)
                       (= (length (directory-files "/tmp/testing/")) 2))))
    (user-error "%s already exists and isn't empty" path))
  (magit-worktree-checkout path
                           (let ((inhibit-magit-refresh t))
                             (forge-branch-pullreq pullreq))))

;;; Misc

;;;###autoload
(defun forge-list-notifications ()
  "List notifications."
  (interactive)
  (magit-mode-setup #'forge-notifications-mode))

;;;###autoload
(defun forge-add-pullreq-refspec ()
  "Configure Git to fetch all pull-requests.
This is done by adding \"+refs/pull/*/head:refs/pullreqs/*\"
to the value of `remote.REMOTE.fetch', where REMOTE is the
upstream remote.  Also fetch from REMOTE."
  (interactive)
  (let* ((repo    (forge-get-repository t))
         (remote  (oref repo remote))
         (fetch   (magit-get-all "remote" remote "fetch"))
         (refspec (oref-default repo pullreq-refspec)))
    (if (member refspec fetch)
        (message "Pull-request refspec is already active")
      (magit-call-git "config" "--add"
                      (format "remote.%s.fetch" remote)
                      refspec)
      (magit-git-fetch remote (magit-fetch-arguments)))))

;;;###autoload
(defun forge-reset-database ()
  "Move the current database file to the trash.
This is useful after the database scheme has changed, which will
happen a few times while the forge functionality is still under
heavy development."
  (interactive)
  (when (and (file-exists-p forge-database-file)
             (yes-or-no-p "Really trash Forge's database file? "))
    (when forge--db-connection
      (emacsql-close forge--db-connection))
    (delete-file forge-database-file t)
    (magit-refresh)))

;;; _
(provide 'forge-commands)
;;; forge-commands.el ends here
