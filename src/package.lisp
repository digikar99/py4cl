
;;;; package.lisp

(defpackage #:py4cl
  (:use #:cl #:iterate)
  (:shadowing-import-from #:iterate #:as #:for)
  (:export ; python-process
   #:pystart
   #:pystop
   #:python-alive-p
   #:python-start-if-not-alive
   #:pyinterrupt)
  (:export ; callpython
   #:pyerror
   #:raw-pyeval
   #:raw-pyexec
   #:pyeval
   #:pyexec
   #:pycall
   #:pymethod 
   #:pygenerator 
   #:pyslot-value 
   #:pyhelp 
   #:pyversion-info
   #:chain
   #:chain*
   #:pysetf)
  (:export ; import-export
   #:pymethod-list 
   #:pyslot-list 
   #:defpyfun  
   #:defpymodule 
   #:defpyfuns
   #:export-function)
  (:export ; lisp-classes
   #:python-getattr)
  (:export ; config 
   #:*config*
   #:initialize
   #:save-config
   #:load-config
   #:config-var
   #:pycmd
   #:numpy-pickle-location
   #:numpy-pickle-lower-bound
   #:py-cd))
