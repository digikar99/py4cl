(py4cl2:defpymodule "math")
(defpackage :py4cl2-tests
  (:use :cl :clunit :py4cl2 :iterate)
  (:export :run))
(in-package :py4cl2-tests)

#.(when (find-package :named-readtables)
    `(,(find-symbol "IN-READTABLE" :named-readtables) :common-lisp))

(defsuite py4cl ())
;; Unable to test interrupt on CCL: see (deftest interrupt
#-ccl (defsuite process-interrupt (py4cl))
(defsuite callpython-raw (py4cl))
(defsuite callpython-utility (py4cl))
(defsuite callpython-chain (py4cl))
(defsuite callpython-remote (py4cl))
(defsuite import-export (py4cl))
(defsuite pickle (py4cl))
(defsuite process-basic (py4cl))
(defsuite objects (py4cl))
(defsuite numpy-ufunc (py4cl))
(defsuite py4cl-config (py4cl))

(py4cl2:pystart)
(defvar *pyversion* (py4cl2:pyversion-info))
;; so that calling this does not mess up other tests: autostarts in particular
(py4cl2:pystop)

(defun run (&optional interactive? result-for)
  "Run all the tests for py4cl2."
  (run-suite 'py4cl :use-debugger interactive?))

;; ======================== PROCESS-BASIC =====================================

(deftest start-and-alive-p (process-basic)
  (assert-false (py4cl2:python-alive-p))
  (py4cl2:pystart)
  (assert-true (py4cl2:python-alive-p)))

(deftest stop (process-basic)
  (py4cl2:pystop)
  (assert-false (py4cl2:python-alive-p))
  (py4cl2:pystop))

;; ======================== CALLPYTHON-RAW =====================================

(deftest raw-autostart (callpython-raw)
  (py4cl2:pystop)
  (py4cl2:raw-pyeval "'hello'")
  (assert-true (py4cl2:python-alive-p))
  (py4cl2:pystop)
  (py4cl2:raw-pyexec "import sys")
  (assert-true (py4cl2:python-alive-p))
  (py4cl2:pystop))

(deftest raw-io-flush (callpython-raw)
  (assert-equalp "hello" (py4cl2:raw-pyeval "'hello'"))
  (assert-equalp "world" (py4cl2:raw-pyeval "'world'"))
  (py4cl2:pyexec "import sys")
  (assert-equalp "hello world"
                 (with-python-output 
                   (py4cl2:raw-pyexec "sys.stdout.write(\"hello world\")")))
  (assert-equalp "testing"
                 (with-python-output 
                   (py4cl2:raw-pyexec "sys.stdout.write(\"testing\")"))))

;; If locks and synchronization are not implemented properly, this
;; would likely fail; in fact, SBCL itself seems to stop
(deftest with-python-output-stress-test (callpython-raw)
  (iter (repeat 10000) (with-python-output (pyexec "print('hello')"))))

(deftest eval-integer (callpython-raw)
  (let ((result (py4cl2:raw-pyeval "1 + 2 * 3")))
    (assert-true (typep result 'integer))
    (assert-equalp 7 result)))

(deftest eval-malformed (callpython-raw)
  (assert-condition py4cl2:pyerror
      (py4cl2:raw-pyeval "1 + ")))

(deftest eval-real (callpython-raw)
  (let ((result (py4cl2:raw-pyeval "1.3 + 2.2")))
    (assert-true (typep result 'real))
    (assert-equalp 3.5 result)))

(deftest eval-vector (callpython-raw)
  (let ((result (py4cl2:raw-pyeval "[i**2 for i in range(4)]")))
    (assert-true (typep result 'array))
    (assert-equalp #(0 1 4 9) result)))

(deftest eval-list (callpython-raw)
  (let ((result (py4cl2:raw-pyeval "(1,2,3)")))
    (assert-true (typep result 'cons))
    (assert-equalp '(1 2 3) result)))

;; Check passing strings, including quote characters which need to be escaped
(deftest eval-string (callpython-raw)
  (assert-equalp "say \"hello\" world"
                 (py4cl2:raw-pyeval "'say \"hello\"' + ' world'")))

(deftest eval-string-newline (callpython-raw)
  (let ((str "hello
world"))
    (assert-equalp str (py4cl2:raw-pyeval (py4cl2::pythonize str)))))

(deftest eval-format-string (callpython-raw)
  (assert-equalp "foo"
      (py4cl2:raw-pyeval (py4cl2::pythonize "foo"))))

;; This tests whether outputs to stdout mess up the return stream
(deftest eval-print (callpython-raw)
  (unless (= 2 (first *pyversion*))
    ;; Should return the result of print, not the string printed
    (assert-equalp nil
        (py4cl2:raw-pyeval "print(\"hello\")")
				"This fails with python 2")))

(deftest unicode-string-type (callpython-raw)
  ;; Python 2 and python 3 handle unicode differently
  ;; This just catches the use of unicode type strings in python2
  ;; not the use of unicode characters
  (assert-equal "test unicode"
                (py4cl2:pyeval "u'test unicode'"))
  (assert-equal 3
                (gethash "pizza"
                         (py4cl2:pyeval "{u'pizza': 3}"))))

(deftest eval-ratios (callpython-raw)
  (assert-equalp 1/2 (py4cl2:pyeval 1/2)) ; round trip
  (assert-equalp 1/4 (py4cl2:pyeval 1/2 "/" 2)) ; manipula-ble
  ;; Complex ratios not supported in python so converts to floats
  (assert-equality #'= #C(0.5 1.0)
    (py4cl2:pyeval #C(1 2) "*" 1/2)))

;; ======================== CALLPYTHON-UTILITY =====================================

(deftest pyeval-params (callpython-utility)
  ;; Values are converted into python values
  (let ((a 4)
        (b 7))
    (assert-equalp 11
        (py4cl2:pyeval a "+" b)))

  ;; Arrays can also be passed
  (assert-equalp #2A((1 2) (3 4))
    (py4cl2:pyeval #2A((1 2) (3 4))))

  (assert-equalp #2A((2 4) (6 8))
    (py4cl2:pyeval #2A((1 2) (3 4)) "*" 2))

  (assert-equalp #3A(((2 4) (7 8)) ((8 5) (1 6)))
    (py4cl2:pyeval #3A(((1 3) (6 7)) ((7 4) (0 5)))  "+" 1))

  ;; Test handling of real numbers in arrays
  (assert-equalp #(1.0 2.0)
      (py4cl2:pyeval (vector 1.0 2.0)))

  ;; Test empty arrays
  (assert-equalp #()
                 (py4cl2:pyeval #()))

  ;; Unless the values are strings
  (let ((str "hello"))
    (assert-condition py4cl2:pyerror
        (py4cl2:pyeval "len(" str ")"))  ; "len(hello)"

    ;; To pass a string to python, run through pythonize:
    (assert-equalp 5
        (py4cl2:pyeval "len(" (py4cl2::pythonize str) ")"))))

(deftest pyeval-complex-values (callpython-utility)
  ;; Single values
  (assert-equality #'= #C(1 2)
    (py4cl2:pyeval #C(1 2)))
  (assert-equality #'= #C(1 -2)
    (py4cl2:pyeval #C(1 -2)))
  (assert-equality #'= #C(-1 -2)
    (py4cl2:pyeval #C(-1 -2)))

  ;; Expressions. Tested using multiply to catch things like
  ;; "1+2j * 2+3j -> 1+7j rather than (-4+7j)
  ;; Note: Python doesn't have complex integers, so all returned
  ;;       values could be floats
  (assert-equality #'= #C(-4 7)
    (py4cl2:pyeval #C(1 2) "*" #C(2 3)))
  (assert-equality #'= #C(4 7)
    (py4cl2:pyeval #C(1 -2) "*" #C(-2 3)))
  
  ;; Lists of complex numbers
  (assert-equality #'= #C(6 9)
    (py4cl2:pyeval "sum(" (list #C(1 2) #C(2 3) #C(3 4))  ")")))

(deftest pyeval-return-numpy-types (callpython-utility)
  (py4cl2:pyexec "import numpy as np")
  (assert-equalp 42.0
      (py4cl2:pyeval "np.float64(42.0)")))

(deftest pyeval-hash-table-from-dict (callpython-utility)
  ;; Simple keys
  (let ((table (py4cl2:pyeval "{1:2, 2:3}")))
    (assert-equalp 2
                   (gethash 1 table))
    (assert-equalp 3
                   (gethash 2 table)))
  
  ;; Ensure values are being lispified
  (let ((table (py4cl2:pyeval "{1:[1,2,3]}")))
    (assert-equalp #(1 2 3)
                   (gethash 1 table)))
  
  ;; Ensure keys are being lispified and string keys work
  (let ((table (py4cl2:pyeval "{\"test\":42}")))
    (assert-equalp 42
                   (gethash "test" table))))

(deftest setf-eval (callpython-utility)
  (setf (py4cl2:pyeval "test_value") 42) ; Set a variable
  (assert-equalp 42
                 (py4cl2:pyeval "test_value")))  


(deftest pyexec (callpython-utility)
  (unless (= 2 (first *pyversion*))
      (assert-equalp nil
          (py4cl2:pyexec "print(\"hello\")")
        "This fails with python 2"))
  (assert-equalp nil ; in case someone makes this a macro some day!
      (let ((module "sys")) (py4cl2:pyexec "import " module)))
  (assert-equalp '("hello" 5) ; in case someone makes this a macro some day!
      (let ((a "'hello'") (b 5))
        (py4cl2:pyexec "temp1 = " a)
        (py4cl2:pyexec "temp2 = " b)
        (py4cl2:pyeval "(temp1, temp2,)"))))

(deftest pycall-autostart (callpython-utility)
  (py4cl2:pystop)
  (py4cl2:pycall "int" "5")
  (assert-true (py4cl2:python-alive-p))
  (py4cl2:pystop))

(deftest pycall-io-flush (callpython-utility)
  (assert-equalp 5 (py4cl2:pycall "int" "5"))
  (assert-equalp "world" (py4cl2:pycall "str" "world"))
  (let ((py4cl2::*py4cl-tests* t))
    (py4cl2:pystop)
    (py4cl2:pyexec "import sys")
    (assert-equalp "hello world"
        (with-python-output (py4cl2:pycall "sys.stdout.write" "hello world")))
    (assert-equalp "testing"
        (with-python-output (py4cl2:pycall "sys.stdout.write" "testing")))))

(deftest pycall-one-arg-int (callpython-utility)
  (assert-equalp 42
      (py4cl2:pycall "abs" -42)))

(deftest pycall-one-arg-list (callpython-utility)
  (assert-equalp 9
      (py4cl2:pycall "sum" '(3 2 4))))

(deftest pycall-one-arg-string (callpython-utility)
  (assert-equalp #("h" "e" "l" "l" "o")
      (py4cl2:pycall "list" "hello")))

(deftest pycall-dotted-function (callpython-utility)
  (py4cl2:pyexec "import math")
  (assert-equalp (sqrt 42)
      (py4cl2:pycall "math.sqrt" 42)))

(deftest pycall-lambda-function (callpython-utility)
  (assert-equalp 16
      (py4cl2:pycall "lambda x: x*x" 4)))

(deftest pycall-lambda-function-two-args (callpython-utility)
  (assert-equalp 10
      (py4cl2:pycall "lambda x, y: x*y - y" 3 5)))

(deftest pycall-lambda-keywords (callpython-utility)
  (assert-equalp -1
      (py4cl2:pycall "lambda a=0, b=1: a-b" :b 2 :a 1))
  (assert-equalp 1
      (py4cl2:pycall "lambda a=0, b=1: a-b" :a 2 :b 1)))

(deftest pycall-with-lambda-callback (callpython-utility)
  ;; Define a function in python which calls its argument
  (py4cl2:pyexec "runme = lambda f: f()")
  ;; Pass a lambda function to pycall
  (assert-equalp 42
      (py4cl2:pycall "runme" (lambda () 42))))

(deftest pycall-string (callpython-utility)
  (assert-equalp "hello" (py4cl2:pycall "str" "hello")))

(deftest pycall-symbol-as-fun-name (callpython-utility)
  (let ((py4cl2::*py4cl-tests* t))
    (py4cl2:pystop)
    (assert-equalp "5" (py4cl2:pycall 'str 5))
    (py4cl2:pyexec "import sys")
    (assert-equalp "hello world"
        (with-python-output (py4cl2:pycall 'sys.stdout.write "hello world")))))


(deftest pycall-hash-table-empty (callpython-utility)
  (assert-equalp "{}"
      (py4cl2:pycall "str" (make-hash-table))))

(deftest pycall-hash-table-values (callpython-utility)
  (let ((table (make-hash-table)))
    (setf (gethash "test" table) 3
          (gethash "more" table) 42)
    (assert-equalp 42
        (py4cl2:pycall "lambda d: d[\"more\"]" table))
    (assert-equalp 3
        (py4cl2:pycall "lambda d: d[\"test\"]" table))
    (assert-equalp 2
        (py4cl2:pycall "len" table))))

(deftest pymethod (callpython-utility)
  (assert-equalp 3
      (py4cl2:pymethod '(1 2 3) '__len__))
  (assert-equalp "hello world"
      (py4cl2:pymethod "hello {0}" 'format "world")))

(deftest pygenerator (callpython-utility)
  (assert-equalp "<class 'generator'>"
      (slot-value (py4cl2:pygenerator #'identity 3) 'type))
  (py4cl2:pyexec "
def foo(gen):
  return list(gen)")
  (assert-equalp #(1 2 3 4)
      (let ((gen (py4cl2:pygenerator (let ((x 0)) (lambda () (incf x)))
                                    5)))
        (py4cl2:pycall 'foo gen)))
  (assert-equalp #(#\h #\e #\l #\l #\o) 
      (let ((gen (py4cl2:pygenerator (let ((str (make-string-input-stream "hello")))
                                      (lambda () (read-char str nil)))
                                    nil)))
        (py4cl2:pycall 'foo gen))))

(deftest pyslot-value (callpython-utility)
  (assert-equalp 5
      (progn
        (py4cl2:pyexec "a=5")
        (py4cl2:pyslot-value "a" 'real)))
  (py4cl2:pyexec "
class Foo:
  def __init__(self):
    self.a = 5
    self.b = 10
temp = Foo()")
  (assert-equalp '(5 10)
      (let ((s 'b) (temp (py4cl2:pycall "Foo")))
        (list (py4cl2:pyslot-value "temp" 'a)
              (py4cl2:pyslot-value temp s)))))

;; ========================= CALLPYTHON-CHAIN ==================================


;; Shorter more convenient slicing
(py4cl2:defpyfun "slice")

(deftest chain (callpython-chain)
  (assert-equalp "Hello world"
      (py4cl2:chain "hello {0}" (format "world") (capitalize)))
  (assert-equalp "hello world"
      (let ((format-str "hello {0}")
            (argument "world"))
        (py4cl2:chain* format-str `(format ,argument))))
  (assert-equalp "result: 3"
      (py4cl2:chain* "result: {0}" `(format ,(+ 1 2))))
  (assert-equalp 3
      (py4cl2:chain (slice 3) stop))

  ;; Anything not a list or a symbol is put between [] brackets (__getitem__)
  (assert-equalp "o"
      (py4cl2:chain (aref "hello" 4)))

  ;; [] operator for indexing and slicing (alias for __getitem__)
  
  (assert-equalp "l"
      (py4cl2:chain (aref "hello" 3)))
  (assert-equalp 3
      (py4cl2:chain (aref #2A((1 2) (3 4))
                         1 0)))
  (assert-equalp #(4 5)
      (py4cl2:chain (aref #2A((1 2 3) (4 5 6))
                          1 (slice 0 2))))

  (let ((dict (py4cl2:pyeval "{\"hello\":\"world\", \"ping\":\"pong\"}")))
    (assert-equalp "world"
        (py4cl2:chain* `(aref ,dict "hello")))
    (assert-equalp "pong"
        (py4cl2:chain* `(aref ,dict "ping")))))
  
(deftest chain-keywords (callpython-chain)
  (py4cl2:pyexec
   "def test_fn(arg, key=1):
       return arg * key")

  (assert-equalp 3
      (py4cl2:chain (test-fn 3)))
  (assert-equalp 6
      (py4cl2:chain (test-fn 3 :key 2)))

  (py4cl2:pyexec
   "class testclass:
      def run(self, dummy = 1, value = 42):
        return value")

  (assert-equalp 42
      (py4cl2:chain (testclass) (run)))

  (assert-equalp 31
      (py4cl2:chain (testclass) (run :value 31))))


(deftest chain-strings (callpython-chain)
  (py4cl2:pyexec
   "class TestClass:
      def doThing(self, dummy = 1, value = 42):
        return value")
  
  (assert-equalp 42
      (py4cl2:chain ("TestClass") ("doThing")))

  (assert-equalp 31
      (py4cl2:chain ("TestClass") ("doThing" :value 31))))

(defclass test-class () ((value :initarg :value)))
(defmethod python-getattr ((object test-class) slot-name)
  (cond
    ((string= slot-name "value") ; data member
      (slot-value object 'value))
    ((string= slot-name "func")  ; method, return a function
      (lambda (arg) (* 2 arg)))
    (t (call-next-method)))) ; Otherwise go to next method
(deftest chain-nested (callpython-chain)
  (assert-equal 42
      (let ((instance (make-instance 'test-class :value 21))) 
        (chain* `((@ ,instance func) (@ ,instance value))))))

(deftest setf-chain (callpython-chain)
  ;; Define an empty class which can be modified
  (py4cl2:pyexec "
class testclass:
  pass")
  
  (let ((obj (py4cl2:chain (testclass))))
    (setf (py4cl2:chain* obj 'data-attrib) 21)
    (assert-equalp 21
        (py4cl2:chain* obj 'data-attrib))))

;; ========================= CALLPYTHON-REMOTE =================================

(deftest with-remote-objects (callpython-remote)
  (assert-equalp 'py4cl2::python-object
      (type-of (py4cl2:with-remote-objects (py4cl2:pyeval "1+2"))))
  (assert-equalp 3
      (py4cl2:with-remote-objects* (py4cl2:pyeval "1+2")))
  (assert-equalp 'py4cl2::python-object
      (type-of (py4cl2:with-remote-objects 
                 (py4cl2:with-remote-objects 
                   (py4cl2:pyeval "1+2"))
                 (py4cl2:pyeval "1+2")))))

(deftest callback-in-remote-objects (callpython-remote)
  ;; Callbacks send values to lisp in remote-objects environments
  (assert-equalp 6
      (py4cl2:with-remote-objects*
        (py4cl2:pycall (lambda (x y) (* x y)) 2 3))))


;; ========================== IMPORT-EXPORT ====================================


;; more extensive tests for defpyfun and defpymodule are required
(py4cl2:defpyfun "sum" "" :lisp-fun-name "PYSUM")
(py4cl2:defpyfun "Fraction" "fractions")
(py4cl2:defpyfun "gcd" "fractions" :as "g")

(deftest defpyfun (import-export)
  (py4cl2:pystop) ; taking "safety" into account
  (assert-equalp 1/2 (fraction :numerator 1 :denominator 2))
  (py4cl2:pystop) ; taking "safety" into account
  (assert-equalp 1 (g :a 5 :b 6))
  (assert-equalp 1 (py4cl2:pycall "g" 5 6)) ; not safe!
  (py4cl2:pystop) ; taking "safety" into account
  (assert-equalp 6 (pysum '(2 1 3))))

(eval-when (:compile-toplevel)
  (pyexec
   "def allNulls(a=[], b=(), c=False, d=None):
  assert type(a)==list
  assert type(b)==tuple
  assert type(c)==bool
  assert type(d)==type(None)
  return True"))
(defpyfun "allNulls")
(deftest defpyfun-null (import-export)
  (pyexec
   "def allNulls(a=[], b=(), c=False, d=None):
  assert type(a)==list
  assert type(b)==tuple
  assert type(c)==bool
  assert type(d)==type(None)
  return True")
  (assert-true (all-nulls)))

(deftest defpymodule-math (import-export)
  (assert-equalp (cos 45) (math:cos 45)))

(eval-when (:compile-toplevel)
  (py4cl2:pyexec "def foo(A, b): return True")
  (py4cl2:pyexec "def bar(a=1, b=2, **kwargs): return kwargs"))
(py4cl2:defpyfun "foo")
(py4cl2:defpyfun "bar")

(deftest defpyfun-names (import-export)
  (py4cl2:pyexec "
def foo(A, b):
  return True")
  (assert-true (foo :a 4 :b 3))
  (py4cl2:pyexec "def bar(a=1, b=2, **kwargs): return kwargs")
  (assert-equal '() (alexandria:hash-table-alist (bar)))
  (assert-equal '() (alexandria:hash-table-alist (bar :a 3)))
  (assert-equal '(("c" . 3)) (alexandria:hash-table-alist (bar :c 3))))

;; Call python during callback
(deftest python-during-callback (callpython-utility)
  (py4cl2:export-function
   (lambda () (py4cl2:pyeval "42"))
   "test")
  (assert-equalp "42"
      (py4cl2:pyeval "test()")))

;; Simple callback function
(defun test-func ()
  42)

(deftest callback-no-args (import-export)
  (py4cl2:export-function #'test-func "test")
  (assert-equalp 42
      (py4cl2:pyeval "test()")))

;; Even simpler function returning NIL
(defun nil-func ()
  nil)

(deftest callback-no-args-return-nil (import-export)
  (py4cl2:export-function #'nil-func "test_nil")
  (assert-equalp nil
      (py4cl2:pyeval "test_nil()")))

;; Python can't eval write-to-string's output "3.141592653589793d0"
(deftest callback-return-double (import-export)
  (py4cl2:export-function (lambda () pi) "test")
  (assert-equalp 3.1415927
      (py4cl2:pyeval "test()")))

(deftest callback-one-arg (import-export)
  (py4cl2:export-function (lambda (x) (* 2 x)) "double")
  (assert-equalp 4
      (py4cl2:pyeval "double(2)")))

(deftest callback-two-args (import-export)
  (py4cl2:export-function (lambda (x y) (/ x y)) "div")
  (assert-equalp 3
      (py4cl2:pyeval "div(6, 2)")))

(deftest callback-many-args (import-export)
  (py4cl2:export-function #'+ "add")
  (assert-equalp 15
      (py4cl2:pyeval "add(2, 4, 6, 3)")))

(deftest callback-seq-arg (import-export)
  (py4cl2:export-function #'reverse "reverse")
  (assert-equalp '(3 1 2 4)
      (py4cl2:pyeval "reverse((4,2,1,3))"))
  (assert-equalp #(3 1 2 4)
      (py4cl2:pyeval "reverse([4,2,1,3])")))

(deftest callback-keyword-arg (import-export)
  (py4cl2:export-function (lambda (&key setting) setting) "test")
  (assert-equalp nil
      (py4cl2:pyeval "test()"))
  (assert-equalp 42
      (py4cl2:pyeval "test(setting=42)")))


;; Call python during callback
(deftest python-during-callback (import-export)
  (py4cl2:export-function
   (lambda () (py4cl2:pyeval "42"))
   "test")
  (assert-equalp "42"
      (py4cl2:pyeval "test()")))


;; ============================= OBJECTS =======================================


(deftest python-objects (objects)
  ;; Define a simple python class containing a value
  (py4cl2:pyexec
"class Test:
  pass

a = Test()
a.value = 42")

  ;; Check that the variable has been defined
  (assert-equalp 42
                 (py4cl2:pyeval "a.value"))

  ;; Implementation detail: No objects stored in python dict
  (assert-equalp 0
                 (py4cl2:pyeval "len(_py4cl_objects)"))
  
  ;; Evaluate and return a python object
  (let ((var (py4cl2:pyeval "a")))
    ;; Implementation detail: Type of returned object
    (assert-equalp 'PY4CL2::PYTHON-OBJECT
                   (type-of var))
    
    ;; Implementation detail: Object is stored in a dictionary
    (assert-equalp 1
                   (py4cl2:pyeval "len(_py4cl_objects)"))

    ;; Can pass to eval to use dot accessor
    (assert-equalp 42
                   (py4cl2:pyeval var ".value"))

    ;; Can pass as argument to function
    (assert-equal 84
                  (py4cl2:pycall "lambda x : x.value * 2" var)))
  
  ;; Trigger a garbage collection so that VAR is finalized.
  ;; This should also delete the object in python
  (tg:gc :full t)

  ;; Implementation detail: dict object store should be empty
  ;; Note: This is dependent on the CL implementation. Trivial-garbage
  ;; doesn't seem to support ccl
  #-clozure (assert-equalp 0
                (py4cl2::pyeval "len(_py4cl_objects)")))

(deftest python-del-objects (objects)
    ;; Check that finalizing objects doesn't start python
  (py4cl2:pystart)
  (py4cl2:pyexec
"class Test:
  pass

a = Test()")
  (let ((var (py4cl2:pyeval "a")))
    ;; Implementation detail: Type of returned object
    (assert-equalp 'PY4CL2::PYTHON-OBJECT
        (type-of var))
    
    (py4cl2:pystop)
    (assert-false (py4cl2:python-alive-p)))
  
  ;; VAR out of scope. Make sure it's finalized
  (tg:gc :full t)
  
  (assert-false (py4cl2:python-alive-p)))

;;; Passing unknown lisp objects to python

(defstruct test-struct
  x y)

(deftest lisp-structs (objects)
  ;; Create a struct and pass to Python
  (let ((result (py4cl2:pycall
                 "lambda x: x"
                 (make-test-struct :x 1 :y 2))))

    ;; Check we got back the structure
    (assert-true (typep result 'test-struct))
    (assert-equalp 1
                   (test-struct-x result))
    (assert-equalp 2
                   (test-struct-y result))))

(defclass test-class ()
  ((value :initarg :value)
   (thing :initarg :thing)))

;; Define a method to handle slot access from python
(defmethod py4cl2:python-getattr ((object test-class) slot-name)
  (cond
    ((string= slot-name "value")
     (slot-value object 'value))
    ((string= slot-name "thing")
     (slot-value object 'thing))
    ((string= slot-name "func")
     (lambda (arg) (* 2 arg)))
    (t (call-next-method))))

(deftest lisp-class-slots (objects)
  (let ((object (make-instance 'test-class :thing 23 :value 42)))
    ;; Slot access
    (assert-equalp 23
        (py4cl2:pycall "lambda x : x.thing" object))
    (assert-equalp 42
        (py4cl2:chain* object 'value))

    ;; Function (method) call
    (assert-equalp 42
        (py4cl2:chain* object `(func 21))))
    
  ;; The handler should work for other objects of the same class (class-of)
  (let ((object2 (make-instance 'test-class :thing "hello" :value 314)))
    (assert-equalp "hello"
                   (py4cl2:chain* object2 'thing))))


;; Class inheriting from test-class
(defclass child-class (test-class)
  ((other :initarg :other)))

;; Define method which passes to the next method if slot not recognised
(defmethod py4cl2:python-getattr ((object child-class) slot-name)
  (cond
    ((string= slot-name "other")
     (slot-value object 'other))
    (t (call-next-method))))

(deftest lisp-class-inherit (objects)
  (let ((object (make-instance 'child-class :thing 23 :value 42 :other 3)))
    (assert-equalp 23
        (py4cl2:pycall "lambda x : x.thing" object))
    (assert-equalp 42
        (py4cl2:chain* object 'value))
    (assert-equalp 3
        (py4cl2:chain* object 'other))))

;; ============================== PICKLE =======================================

(deftest transfer-multiple-arrays (pickle)
  (when (and (py4cl2:config-var 'py4cl2:numpy-pickle-location)
             (py4cl2:config-var 'py4cl2:numpy-pickle-lower-bound))
    (let ((dimensions `((,(py4cl2:config-var 'py4cl2:numpy-pickle-lower-bound))
                        (,(* 5 (py4cl2:config-var 'py4cl2:numpy-pickle-lower-bound))))))
      (assert-equalp dimensions
                     (mapcar #'array-dimensions 
                             (py4cl2:pyeval
                              (list (make-array (first dimensions) :element-type 'single-float)
                                    (make-array (second dimensions) :element-type 'single-float))))
                     "No bound or location for pickling."))))

(deftest transfer-without-pickle (pickle)
  (unless (and (py4cl2:config-var 'py4cl2:numpy-pickle-location)
             (py4cl2:config-var 'py4cl2:numpy-pickle-lower-bound))
    (assert-equalp '(100000)
                   (array-dimensions
                    (py4cl2:pyeval (make-array 100000 :element-type 'single-float)))
      "Pickle bound and location is present.")))

;; ========================= NUMPY-UFUNC =======================================

(py4cl2:pyexec "
try:
  import numpy
  found = True
except ImportError:
  found = False")
(when (py4cl2:pyeval "found")
  (py4cl2:defpyfun "abs" "numpy" :lisp-fun-name "NUMABS")
  (deftest numpy-ufunc-abs (numpy-ufunc)
    (assert-equalp #(1 2 3) (numabs #(-1 2 -3))))
  (py4cl2:defpyfun "add" "numpy" :lisp-fun-name "NUMADD")
  (deftest numpy-ufunc-abs (numpy-ufunc)
    (assert-equalp #(4 5 6) (numadd #(1 2 3) 3))))

;; ==================== PROCESS-INTERRUPT ======================================

;; Unable to test on CCL:
;; Stream #<BASIC-CHARACTER-OUTPUT-STREAM UTF-8 (PIPE/36) #x3020019EE9AD> is private to #<PROCESS repl-thread(12) [Sleep] #x302000AC72FD>

#-ccl (deftest interrupt (process-interrupt)
        (let ((py4cl2::*py4cl-tests* t))
          (py4cl2:pystop)
          (py4cl2:pyexec "
class Foo():
  def foo(self):
    import time
    import sys
    sys.stdout.write('hello')
    sys.stdout.flush()
    time.sleep(5)
    return")
          (assert-equalp "hello"
              (let* ((rv nil)
                     (mon-thread (bt:make-thread
                                  (lambda ()
                                    (setq rv
                                          (with-python-output (py4cl2:pycall "Foo().foo")))))))
                (sleep 1)
                (py4cl2:pyinterrupt)
                (bt:join-thread mon-thread)
                rv))
          (assert-equalp "hello"
              (let* ((rv nil)
                     (mon-thread (bt:make-thread
                                  (lambda ()
                                    (setq rv
                                          (with-python-output
                                            (py4cl2:pymethod (py4cl2:pycall "Foo") 'foo)))))))
                (sleep 1)
                (py4cl2:pyinterrupt)
                (bt:join-thread mon-thread)
                rv)))

    ;; Check if no "residue" left

  (assert-equalp 5 (py4cl2:pyeval 5)))

(deftest config-change (py4cl-config)
  (let ((original-config (copy-tree *config*)))
    (with-python-output
      (setf (py4cl2:config-var 'py4cl2:numpy-pickle-location) "tmp")
      (setf (py4cl2:config-var 'py4cl2:numpy-pickle-lower-bound) 10000)
      (setf (py4cl2:config-var (intern "NON-EXISTENT" :py4cl2)) "non-existent")
      (assert-equal "tmp"
          (py4cl2:pyeval "_py4cl_config['numpyPickleLocation']"))
      (assert-equal 10000
          (py4cl2:pyeval "_py4cl_config['numpyPickleLowerBound']"))
      (assert-equal "non-existent"
          (py4cl2:pyeval "_py4cl_config['nonExistent']"))
      (unintern 'py4cl2::non-existent :py4cl2)
      (setq py4cl2:*config* original-config)
      (py4cl2:save-config))))
