;;; jjsonrpc

;; Copyright (C) 2018 Jinsub Ahn

;; Author: Jinsub Ahn <jinniahn@gmail.com>
;; Created: 04 Nov 2018
;; Version: 1.0
;; Keywords: 
;; X-URL: 


;;; Commentary:

;; test code:
;; (setq jjsonrpc-backend 'http)
;; (setq cmd (list :path nil :module "os" :func "getcwd" :params '()))
;; (setq cmd (list :path nil :module "os" :func "listdir" :params '()))
;; (setq name "jinni")
;; (setq call-string "ls")

;; (jjsonrpc--backend-shell-command cmd)
;; (jjsonrpc--backend-compile cmd)
;; (jjsonrpc--backend-simple-http cmd)
;; (jjsonrpc--backend-proc cmd #'(lambda (x) (message (json-encode x))))

;; backends:
;;   - http, shell-command, compile, async-proc
;; (let ((jjsonrpc-backend 'http)) (jjsonrpc-run cmd))
;;
;; change server addr:
;; (let ((jjsonrpc-server "localhost" (jjsonrpc-port 4001) (jjsonrpc-backend 'http)) (jjsonrpc-run cmd))

;; (jjsonrpc-sync "os.getcwd")
;; (jjsonrpc-async "os.getcwd" nil nil #'(lambda (x) (setq yyy x) (message "%s" x)))

;; (setq cmd (list :path nil :module "wiki" :func "wiki_data" :params (list (f-expand helm-wiki-dir))))
;; (jjsonrpc--backend-http cmd)
;; (jjsonrpc-run cmd)
;;
;;  (let ((jjsonrpc-backend 'compile)
;;		(cmd (list :path nil :module "emacs.jbugzilla" :func "update_bugzilla" :params '())))
;;	(jjsonrpc--backend-compile cmd))
;;
;; debug mode:
;;
;; (setq jjsonrpc-debug-mode t)

;;; Code:
(require 'json)
(require 'json-rpc)

(defvar jjsonrpc-debug-mode nil "indicate to log in message buffer")

(setf jjsonrpc--rpc nil)
(setq jjsonrpc-connection-map (make-hash-table :test 'equal))
(defvar jjsonrpc-server "localhost")
(defvar jjsonrpc-port 4000)

(defun jjsonrpc-parse-server (url)
  "parse server-url into (list <server-name> <port>)"
  
  (let ((parsed_url (s-split ":" url t)))
    (cond
     ((eq (length parsed_url) 2)
      (list (first parsed_url) (string-to-number (second parsed_url))))
     ((eq (length parsed_url) 1)
      (list (first parsed_url) 4000))
     (t
      (list "localhost" 4000)))))

;; ;; (defun jjsonrpc--rpc-connection ()
;; ;;   (unless jjsonrpc--rpc
;; ;;     (setf jjsonrpc--rpc (json-rpc-connect "localhost" 4000 )))
;; ;;   jjsonrpc--rpc)

;; (defun jjsonrpc--rpc-connection ()
;;   (let ((server-url
;; 	(if (boundp 'jjsonrpc-server)
;; 	    jjsonrpc-server
;; 	  (format "%s:%d" jjsonrpc-server jjsonrpc-port))))
;;     (when (not (gethash server-url jjsonrpc-connection-map))
;;       (let ((conn (apply #'json-rpc-connect (jjsonrpc-parse-server server-url))))
;; 	(puthash server-url conn jjsonrpc-connection-map)))

;;     (let ((conn (gethash server-url jjsonrpc-connection-map)))
;;       (if (json-rpc-live-p conn)
;; 	  conn
;; 	;; or create new
;; 	(let ((conn (apply #'json-rpc-connect (jjsonrpc-parse-server server-url))))
;; 	  (puthash server-url conn jjsonrpc-connection-map)
;; 	  conn)))))

(defvar jjsonrpc-backend 'http "backend of jjsonrpc")

(defun unique-jjsonrpc-name ()
  (let ((finish nil) name)
    (while (not finish)
      (setq name (format "jjsonrpc-%d" (random 100000)))
      (unless (get-buffer (format "*%s*" name))
		(setq finish t)
		name))
    name))

(defun jjsonrpc-create-cmd (func &optional params modulepath)
  "create command for jjsonrpc-run with simple form command"
  
  (let ((default-directory (current-local-directory))
		cmd tokens funcname mod res)

    ;; (setq func "emacs.cc_help.print_prototypes")
    ;; split
    (setq tokens (s-split "\\." func))

    ;; find name & module
    (setq funcname (car (last tokens)))
    (setq mod (s-join "." (remove funcname tokens)))
    (when (s-blank? mod)
      (setq mod nil))

    ;; make cmd
    (list :path modulepath
		  :cwd (if (f-exists? default-directory)
				   default-directory
				 "/")
		  :module mod
		  :func funcname
		  :params params)))

(defun jjsonrpc-handle-res (res)
  (if (plist-get res :error)
      (user-error "jsonrpc error: %s" (plist-get res :error))	
    (plist-get res :result)))

(defun jjsonrpc--kill-buffers ()
  "Kill all other buffers."
  (interactive)
  (mapc 'kill-buffer
		(cl-loop for buf in (buffer-list)
				 when (s-prefix? "*jjsonrpc" (buffer-name buf))
				 collect buf)))

(defun jjsonrpc-run (cmd &optional callback)
  (when jjsonrpc-debug-mode
    (message "jjsonrpc-run: %s %s" (symbol-name jjsonrpc-backend)
             (prin1-to-string cmd)))
  
  (condition-case e
      (pcase jjsonrpc-backend
		('http (jjsonrpc--backend-simple-http cmd))
		('async-shell-command (jjsonrpc--backend-async-shell-command cmd))
		('shell-command (jjsonrpc--backend-shell-command cmd))
		('compile (progn (jjsonrpc--backend-compile cmd) (user-error "cannot execute it further")))
		('async-proc (jjsonrpc--backend-proc cmd callback)))
    (error
     (when jjsonrpc-debug-mode
       (message "error: %s" (prin1-to-string e)))

     ;; fallback
     (if (eq jjsonrpc-backend 'async-proc)
		     (error e)

       ;; try run backend server
       (jjsonrpc--run-http-server)

       ;; try get result by commend
       (jjsonrpc--backend-shell-command cmd)
       ))))

;;
;; backends
;;
(defun jjsonrpc--backend-shell-command (cmd)
  "make json call. it is corresponding to jsonrpcdummy.py"
  (let* ((quoted-cmd (shell-quote-argument (json-encode cmd)))
		 (call-string (concat
					   ;;(format "PYTHONPATH=%s " (getenv "PYTHONPATH"))
					   "echo " quoted-cmd " | "
					   "python3 -m jsonrpcdummy -"))
		 ret)
    (setq ret
		  (let ((default-directory (current-local-directory)))
			(shell-command-to-string call-string)))
    (car (read-from-string ret))))

(defun jjsonrpc--backend-async-shell-command (cmd)
  "make json call. it is corresponding to jsonrpcdummy.py"
  (let* ((quoted-cmd (shell-quote-argument (json-encode cmd)))
		 (call-string (concat
					   ;;(format "PYTHONPATH=%s " (getenv "PYTHONPATH"))
					   "echo " quoted-cmd " | "
					   "python3 -m jsonrpcdummy -"))
		 ret)
	(let ((default-directory (current-local-directory)))
	  (async-shell-command call-string))))

(defun jjsonrpc--backend-compile (cmd)
  "make json call. it is corresponding to jsonrpcdummy.py
It is useful to debug"
  (let* ((quoted-cmd (shell-quote-argument (json-encode cmd)))
		 (call-string (concat "echo " quoted-cmd " | python3 -m jsonrpcdummy -"))
		 ret)
	;; truncate if it too long
	;; | fold -sw 100
	
	(let ((default-directory (current-local-directory)))
	  (compile call-string))))

;; (defun jjsonrpc--backend-http (cmd)
;;   "make json call"
;;   (let ((json-array-type 'list))
;;     (json-rpc (jjsonrpc--rpc-connection) "call_obj" cmd)))

(defun jjsonrpc--backend-simple-http (cmd)
  "jsonrpc library에 의존하지 않고 직접 HTTP로 서버에 요청한다. "
  (let* ((host jjsonrpc-server)
		 (port jjsonrpc-port)
		 (buffer (generate-new-buffer "*json-rpc-console*"))
         process)

    ;; (message "%s %d" jjsonrpc-server port)
    ;; (message "port: %d" (or (and (boundp 'jjsonrpc-server) (string-to-number (second (s-split ":" jjsonrpc-server)))) jjsonrpc-default-port))
    
    (setq process (make-network-process :name (format "json-rpc-%s" host)
                                        :buffer buffer
                                        :host host
                                        :service port
                                        :coding '(utf-8 . utf-8)))
	;; remove buffer
    (setf (process-sentinel process)
          (lambda (proc _)
            (run-at-time 1 nil #'kill-buffer (process-buffer proc))))

    ;; send command
    (with-temp-buffer
      (let ((encoded-cmd
             (concat "{\"jsonrpc\":\"2.0\",\"method\":\"call_obj\",\"params\":["
                     (json-encode cmd)
                     "],\"id\":1}")))
        (insert (format "POST %s HTTP/1.1\r\n" (url-encode-url "/")))
        (insert "Content-Type: application/json\r\n")
        (insert (format "Content-Length: %d\r\n\r\n" (string-bytes encoded-cmd)) encoded-cmd)
        (process-send-region process (point-min) (point-max))))
    
    ;; wait upto 10 sec
    (while (process-live-p process) (accept-process-output process 10))

    ;; parse response
    (with-current-buffer buffer
      (goto-char (point-min))
      (search-forward "\n\n" nil t)
      (if (fboundp 'json-serialize)
          (plist-get
           (json-parse-string (buffer-substring-no-properties (point) (point-max)) :object-type 'plist :array-type 'list :null-object nil)
           :result)
        (let ((json-object-type 'plist)
              (json-array-type 'list))
          (plist-get (json-read) :result))))))

(defun jjsonrpc--backend-proc (cmd res-func &optional name)
  "make json call. it is corresponding to jsonrpcdummy.py"
  
  (let* ((quoted-cmd (shell-quote-argument (json-encode cmd)))
         (default-directory (current-local-directory))
         (call-string (concat
                       ;;"sleep 0.1;"
                       ;;(format "PYTHONPATH=%s " (getenv "PYTHONPATH"))
                       "echo " quoted-cmd " | "
                       "python3 -m jsonrpcdummy -"))
         ret)
    (setq name (or name (unique-jjsonrpc-name)))
    (setq proc (start-process-shell-command name (format "*%s*" name) call-string))

    ;; add process sentinel
    (with-current-buffer (process-buffer proc)
      (setq-local callback-func res-func))

    (set-process-sentinel proc
                          (lambda (proc event)
                            ;;(message event)
                            (setq event (s-trim event))
                            ;; handle result of execution
                            (when (string= event "finished")
                              ;; when process is finished
                              (let (res)
                                (with-current-buffer (process-buffer proc)
                                  (when callback-func
                                    (setq res (car (read-from-string
                                                    (buffer-substring-no-properties
                                                     (point-min)
                                                     (marker-position  (process-mark proc))))))
                                    ;; check error
                                    (condition-case error
                                        (funcall callback-func res)
                                      (error
                                       ;;(warn "cannot run callback function in process sentinel")
                                       ))
                                    ))))

                            ;; remove process buffer
                            (when (or (member event '("finished" "deleted""exited"))
                                      (s-contains? "failed" event))
                              (kill-buffer (process-buffer proc)))
                            ))
    proc))


;; limit size to pass data direct-way.
(setq indirect-data-max-size 1024)

(defun jjsonrpc-make-indirect-data (text)
  (when (> (length text) indirect-data-max-size)
    (let ((tmp (tempfile-generate-file)))
      (with-temp-file tmp
        (insert text))
      (format "file:%s" tmp))))

(defun jjsonrpc-ret-helm-handler (res)
  "handler for j-jsonrpc-async in helm"
  (setq res (car (read-from-string (car res))))
  ;; check error
  (if (plist-get res :error)
      (user-error "jsonrpc error: %s" (plist-get res :error))   
    (plist-get res :result)))


;;
;; public api
;;
;;;###autoload
(defun jjsonrpc-sync (func &optional params modulepath)
  "call python function call"
  ;;Usage:
  (let ((cmd (jjsonrpc-create-cmd func params modulepath))
		res)

    ;; call
    (setq res (jjsonrpc-run cmd))
    (jjsonrpc-handle-res res)))

;;;###autoload
(defun jjsonrpc-async (func &optional params modulepath callback)
  "call python function call"
  ;;Usage:
  (let ((cmd (jjsonrpc-create-cmd func params modulepath))
		res)

    ;; call
    (let ((jjsonrpc-backend 'async-proc))
      (jjsonrpc-run cmd `(lambda (res)
						   (setq res (jjsonrpc-handle-res res))
						   (funcall ,callback res))))))

(defun jjsonrpc-find-source (func)
  "find function where you at.
This function recognizes python file and function name.
Once it got filename, open file and go to where function is."
  (interactive (list
				;; full function name
				(cl-destructuring-bind (beg end) (jinni-thing-at-point-string)
				  (buffer-substring-no-properties (1+ beg) (1- end)))))
  (let* ((default-directory (current-local-directory))
		 ;; split module and func name and find path
		 (module (s-join "." (-drop-last 1 (s-split "\\." func))))
		 (funcname (car (last (s-split "\\." func))))
		 (path (s-trim (shell-command-to-string (format "python3 -c 'import %s;print(%s.__file__)'" module module)))))
	(when (f-exists? path)
	  (with-selected-window (display-buffer (find-file-noselect path))
		(goto-char (point-min))
		(re-search-forward (format "def\s+%s\s*(" funcname) nil t)
		(forward-line 0)
		(pulse-momentary-highlight-one-line (point))		
		))))

(defun jjsonrpc--run-http-server ()
  (interactive)
  (let* ((bufname "*jsonrpc*")
		 (procname "jsonrpc")
		 (buf (get-buffer-create bufname))
		 (bufproc (get-buffer-process buf)))
    
    ;; clear previous resources
    (when bufproc (interrupt-process bufproc))
    (when buf (kill-buffer buf))

    ;; start new process
    (setq bufproc (start-process
				   procname
				   bufname
				   "python3" "-m" "jjsonrpc.server" "-p" (number-to-string jjsonrpc-port)))
	(set-process-query-on-exit-flag bufproc nil)))

(defun jjsonrpc-stop-http-server ()
  "stop http server, which run internally"
  (interactive)
  (let* ((bufname "*jsonrpc*")
		 (buf (get-buffer bufname))
		 (proc (get-buffer-process buf)))
	(when (and proc (process-live-p proc))
	  (kill-process proc)
	  (kill-buffer buf))))

(defun jjsonrpc-make-py-func (path line)
  (interactive (list
				(buffer-file-name)
				(save-excursion
				  (let ((beg (progn (beginning-of-line) (point)))
						(end (progn (end-of-line) (point))))
					(buffer-substring-no-properties beg end)))))

  (when (and path line)

	(let (code)
	  (setq code 
			(jjsonrpc-sync "emacs.py.make_jjsonrpc_sync_func_from_string"
						   (list path line)
						   ))
	  (with-current-buffer (get-buffer-create "*code*")
		(erase-buffer)
		(insert code)
		(display-buffer (current-buffer))
		)
	  
	  (message "copied code"))))

(provide 'jjsonrpc)
;;; jjsonrpc.el ends here
