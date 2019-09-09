---
title: py4cl2
---

---

# Introduction

[py4cl](https://github.com/bendudson/py4cl) is a package by Ben Dudson, aimed at making python libraries availble in Common Lisp,
using streams to communicate with a separate python process - the approach taken by [cl4py](https://github.com/marcoheisig/cl4py). This is
different to the CFFI approach used by [burgled-batteries](https://github.com/pinterface/burgled-batteries),
but has the same goal. 

[py4cl2](https://github.com/digikar99/py4cl2) is an improvement over the original py4cl. (See [Highlights and Limitations](#highlights-and-limitations-of-py4cl).)

Please report the issues on github: [py4cl2](https://github.com/digikar99/py4cl2/issues) or [py4cl](https://github.com/bendudson/py4cl/issues)).


# Highlights and Limitations of `py4cl`

- Speed: About 6500 `(pycall "int" "5")` instructions per second @ 1GHz intel 8750H. 
This shouldn't be a bottleneck if you're planning to run "long" processes in python. (For example, deep learning :). )
- Virtual environments: [`pycmd`](#pycmd) (`*python-command*` in `py4cl`): Choose which python binary to use. Works with miniconda.
- Multiple python processes (not documented here) - parallel execution?
- Tested on SBCL and CCL

<div><img src="readme_slime.png" width="80%" style="margin:auto; display:block;"/></div>
<!-- ![slime-demo-image](readme_slime.png) -->

## Improvements over py4cl
- Changes: several (but not all) names have been shorted from `python-` to `py`; `remote-objects` have been changed to `with-remote-object(s)`. Personal preference for these names stems from:
  - `defpyfun/module` reminds of the equivalent in `burgled-batteries` and `cffi`
  - `py`names are shorter
  - `with-remote` seems more appropriate
  - `chain` and `chain*` with more "uniformity"
- Arguments are imported; submodules can be imported with an option to [defpymodule]. However, this is only possible for python3.
- Improvements in large array transfer speed, using numpy-file-format (see [initialize](#initialize); though this does not beat `remote-objects`, in existence since `py4cl`, 
- Interrupt the python process using [(pyinterrupt)](#pyinterrupt)
- `defpymodule` (previously `import-module`) is works "as-expected" with asdf / `defpackage`.
- stderr and stdout of python process is read asynchronously from a separate thread - this does render the use of `with-output-to-string` useless for wrapping around python functions; a work-around is to set `py4cl2::*py4cl-tests*` to `t` and use `(uiop:process-info-output py4cl::*python*)`. (Refer [tests.lisp](https://github.com/digikar99/py4cl2/blob/master/tests/tests.lisp) for examples.)

- See [TODO].

# Installation

## Dependencies

This fork is possible due to the following (and therefore, depends on):

On the CL side:

- trivial garbage
- iterate
- bordeaux-threads
- cl-json
- parse-number
- uiop (some implementations have an older version of uiop; support for `launch-program` is needed for asynchronous processes)
- [numpy-file-format](https://github.com/marcoheisig/numpy-file-format) *

\* possibly not available on quicklisp (may be see [How to install new packages for common lisp without asdf-install
](https://stackoverflow.com/questions/8441224/how-to-install-new-packages-for-common-lisp-without-asdf-install); in essence, download the github-repo to somewhere asdf can find.)

On python side:

- numpy (optional)

(other packages should be available in a standard python distribution - tested with CPython.)

## Installation

Clone this repository into `~/quicklisp/local-projects/` or other
location where it can be discovered by ASDF:
```sh
git clone https://github.com/digikar99/py4cl2.git
```

Original version by [bendudson](https://github.com/bendudson/py4cl) can be found at: 
```sh
git clone https://github.com/bendudson/py4cl.git
```

However, since then, several changes have been made.

Load into Lisp with
```lisp
(ql:quickload :py4cl2)
```


## Setting up

### `initialize`

On loading this library for the first time, run `initialize` and provide the necessary details.
```lisp
(py4cl2:initialize)
```

(You may want to note the printed information, about the location of config-file. Of course, you can call this function again, but be sure to refill the values.)

The library uses (temporary) pickled .npy files for transferring large numpy arrays efficiently
between lisp and python. This process is IO intensive, writing as much as 100MB or even a GB each time.
Using a ram-disk is recommended for this purpose. ([How to create a ram disk on Linux?](https://unix.stackexchange.com/questions/66329/creating-a-ram-disk-on-linux))

### `*config*` / `config-var`
These values can also be accessed using `*config*` and `config-var`:

```lisp
CL-USER> py4cl2:*config*
((PY4CL2:PYCMD . "/home/user/miniconda3/bin/python")
 (PY4CL2:NUMPY-PICKLE-LOCATION . "/home/user/ram-disk/_numpy_pickle.npy")
 (PY4CL2:NUMPY-PICKLE-LOWER-BOUND . 100000))
CL-USER> (py4cl2:config-var 'py4cl2:numpy-pickle-location)
"/home/user/ram-disk/_numpy_pickle.npy"
CL-USER> (setf (config-var 'py4cl2:pycmd) "python")
"python"
```

Complementary to `config-var` are `save-config` and `load-config`. The latter is called on startup, the config-file exists. `(setf config-var)` calls the former unless it is `pycmd`, as well as asks the python process to load the config, from the config file. (The exception for `pycmd` exists so as to let the users set up project-local environments.)


# Examples and Documentation

```lisp
CL-USER> (use-package :py4cl2)
```

## Python Processes

It all starts with a python process (actually, more than one as well - this use hasn't been documented here.).

### `pycmd`

```lisp
CL-USER> (config-var 'pycmd)
"python"
```

Also see [config-var](#config--config-var).

### `pyversion-info`
```lisp
CL-USER> (pyversion-info)
(3 7 3 "final" 0)
```

### `pyinterrupt`
`(pyinterrupt &optional process)`

A simple `C-c C-c` only interrupts the lisp process from slime - the python process keeps running. `(pyinterrupt)` can be used in these cases to send a SIGINT (2) to the python process.

Also note that if `pyinterrupt` is not called before sending the next form to `eval` or `exec`, the input-output would go out of sync. A known way to get out is to `(pystop)` the python-process.

Therefore, you may want to have `(pyinterrupt)` called on the reception of SIGINT in SLIME:

```lisp
(when (find-package :swank)
  (defvar swank-simple-break)
  (setf (fdefinition 'swank-simple-break)
        (fdefinition (find-symbol "SIMPLE-BREAK" :swank)))
  (defun swank:simple-break
      (&optional (datum "Interrupt from Emacs") &rest args) 
    (py4cl2:pyinterrupt)
    (apply (fdefinition 'swank-simple-break) datum args)))
```

However, I have been unable to get the code to work (by adding to `do-after-load` with as well as without SLIME. Further, people may not like a library to fiddle with their environments - so it might be better to leave it up to the user to set it.

### py-cd
`(py-cd path)`

Equivalent of `slime-cd`, since python is a separate process.

### Other useful functions

#### `pystart`
#### `pystop`
#### `python-alive-p`
#### `python-start-if-not-alive`


## Doing arbitrary things in python

Unlike lisp, python (and most other languages) make a distinction between *statements* and *expressions*: see [Quora](https://www.quora.com/Whats-the-difference-between-a-statement-and-an-expression-in-Python-Why-is-print-%E2%80%98hi%E2%80%99-a-statement-while-other-functions-are-expressions) or [stackoverflow](https://stackoverflow.com/questions/4728073/what-is-the-difference-between-an-expression-and-a-statement-in-python).

A general rule of thumb from there is: if you can print it, or assign it to a variable, then it's an expression, otherwise it's a statement.

Both `pyeval` and `pyexec` take any type of arguments. The `arg` is `pythonize`d if the `arg` is not a `string`, or it is a `string` that can be read into a `real`.

### `raw-pyeval`
`(raw-pyeval &rest strings)`

Concatenates the strings and sends them to the python process for `eval`uation. The concatenation should be a valid python expression. Returns the result of evaluating the expression.

### `raw-pyexec`
`(raw-pyexec &rest strings)`

Concatenates the strings and sends them to the python process for `exec`uation. The concatenation should be a valid python statement. Returns nil.

Note that [one limitation of `pyexec` is that modules imported on the top-level (of python) are not available inside some things](https://stackoverflow.com/questions/12505047/in-python-why-doesnt-an-import-in-an-exec-in-a-function-work). These "some things" include functions.

The following should illustrate this point:
```lisp
CL-USER> (pyexec "import time")
NIL
CL-USER> (pyeval "time.time()")
1.5623434e9
CL-USER> (pyexec "
def foo():
  return time.time()")
NIL
CL-USER> (pyeval "foo()")
; Evaluation aborted on #<PYERROR {100C24DF03}> ;; says 'time' is not defined
CL-USER> (pyeval "time.time()")
1.5623434e9
```
THe workaround in this case is to `import` inside the `def`.

Often times, the two commands above would be tedious - since you'd need to convert objects into their string representations every time. To avoid this hassle, there are the following useful functions.

### `pyeval`
`(pyeval &rest args)`

For python expressions 
```lisp
CL-USER> (pyeval 4 "+" 3)
7
```

There's also `(setf pyeval)`, which unlike `(pyexec)`, can return non-`nil` values.

```lisp
CL-USER> (setf (pyeval "a") "5")
"5"
CL-USER> (pyeval "a")
"5"
```

`pyeval` (and `pyexec`) treats the string as a python string, if it can be parsed into a number.
In fact, in accordance with an internal function `pythonizep`.

```lisp
CL-USER> (pyeval "1.0")
"1.0"
CL-USER> (pyeval "hello")
; Evaluation aborted on #<PYERROR {1003AC0183}>.
```

See also [Doing arbitrary things in python](#doing-arbitrary-things-in-python).

### `pyexec`
`(pyexec &rest args)`

For python statements
```lisp
CL-USER> (pyexec "
if True:
  print(5)
else:
  print(10)")
; 5
NIL
```
`pyexec` (and `pyeval`) treats the string as a python string, if it can be parsed into a number).
In fact, in accordance with an internal function `pythonizep`. (See [pyeval](#pyeval).)

See also [Doing arbitrary things in python](#doing-arbitrary-things-in-python) to learn about `pyeval` and `pyexec`.

## Defining python functions and modules

Rather, we define functions that call python functions.

Names are lispified by converting underscores hyphens, and converting CamelCase to camel-case. Also see [Name Mapping](#name-mapping). 

### `defpyfun`
```lisp
(defpyfun fun-name &optional pymodule-name &key 
  (as fun-name) (lisp-fun-name (lispify-name as))
  (lisp-package *package*) (called-from-defpymodule nil)
  (safety t)
```
`lisp-fun-name` is the name of the symbol that would be `fboundp`ed to the function [that calls the python function].

Example Usage:
```lisp
CL-USER> (defpyfun "Input" "keras.layers" :lisp-fun-name "INP")
INP

CL-USER> (inp :shape '(1 2))
#S(PY4CL2::PYTHON-OBJECT
   :TYPE "<class 'tensorflow.python.framework.ops.Tensor'>"
   :HANDLE 1849)
```

`safety` takes care to import the required function from the required module after python process restarts for some reason. However, this affects speed.

Refer `(describe 'defpyfun)`.

### `defpymodule`
```lisp
(defpymodule pymodule-name &optional import-submodules &key 
  (lisp-package (lispify-name (or as pymodule-name)))
  (reload t) (safety t) (is-submodule nil)
```

`lisp-package` is the name of the symbol that the package would be bound to.

Example Usage:
```lisp
CL-USER> (defpymodule "keras.layers" t :lisp-package "KL")
T

CL-USER> (kl:input :shape '(1 2))
#S(PY4CL2::PYTHON-OBJECT
   :TYPE "<class 'tensorflow.python.framework.ops.Tensor'>"
   :HANDLE 816)
   
CL-USER> (pycall (kl.advanced-activations:softmax/class :input-shape '(1 2))
                 (kl:input :shape '(1 2)))
#S(PY4CL2::PYTHON-OBJECT
   :TYPE "<class 'tensorflow.python.framework.ops.Tensor'>"
   :HANDLE 144)
```

Note that unlike Common Lisp, python has a single namespace. Therefore, currently,
to call a callable (in Python) object, but not defined as a function in Common Lisp,
you'd need to use something like [pycall].

### `defpyfuns`

(Undocumented here.)

## `pyerror`

(Undocumented here.)

## Using functions and methods

### `pycall`
`(pycall fun-name &rest args)`

Equivalent to the lisp `(funcall function &rest arguments)`. Call a python (or lisp! See [generators and lambdas](#generators-and-lambdas)) function.

```lisp
CL-USER> (py4cl2:pycall "print" "hello")
;; hello
NIL
CL-USER> (py4cl2:pycall #'+ 2 3 1)
6
```

Note that `fun-name` can be a name (see [Name Mapping]), a function, or a [callable] python-object. See the example in [defpymodule](#defpymodule).

### `pymethod`
`(pymethod obj method-name &rest args)`

`pymethod` always pythonizes; `method-name` is [name mapped to Python names][Name Mapping].

```lisp
SEQ2SEQ> (pymethod model 'summary) ;; for some "ready" model
__________________________________________________________________________________________________
Layer (type)                    Output Shape         Param #     Connected to                     
==================================================================================================
input_1 (InputLayer)            (None, None, 43)     0                                            
__________________________________________________________________________________________________
input_2 (InputLayer)            (None, None, 64)     0                                            
__________________________________________________________________________________________________
lstm_1 (LSTM)                   [(None, 256), (None, 307200      input_1[0][0]                    
__________________________________________________________________________________________________
lstm_2 (LSTM)                   [(None, None, 256),  328704      input_2[0][0]                    
                                                                 lstm_1[0][1]                     
                                                                 lstm_1[0][2]                     
__________________________________________________________________________________________________
dense_1 (Dense)                 (None, None, 64)     16448       lstm_2[0][0]                     
==================================================================================================
Total params: 652,352
Trainable params: 652,352
Non-trainable params: 0
__________________________________________________________________________________________________
NIL
```

See [pymethod-list](#pymethod-list).

### `pyslot-value`
`(pyslot-value object slot-name)`

```lisp
CL-USER> (pyslot-value model 'input-shape)
#((NIL NIL 43) (NIL NIL 64))
```

See [pyslot-list](#pyslot-list)

Also see [Name Mapping].

### `export-function`
`(export-funtion function python-name)`

Lisp functions can be made available to python code using `export-function`:
```lisp
(py4cl:python-exec "from scipy.integrate import romberg")

(py4cl:export-function (lambda (x) (/ (exp (- (* x x)))
                                      (sqrt pi))) "gaussian")

(py4cl:python-eval "romberg(gaussian, 0.0, 1.0)") ; => 0.4213504
```

### `pyhelp`
`(pyhelp python-object)`

Calls python's `help` function on `python-object`. (NOTE: some descriptions, especially
for modules, are too big to be transferred in a reasonable time.)

## Generators and Lambdas

### `pygenerator`
`(pygenerator function stop-value)`

```lisp
CL-USER> (let ((a 0)) (defun foo () (incf a)))
FOO

CL-USER> (pyeval "[x for x in " (pygenerator #'foo 3) "]")
#(1 2)
```

### lambdas

Lisp functions are `pythonize`d to `LispCallbackObject`s. As the name suggests, python can call LispCallbackObjects (and therefore, lisp functions), just like it is any other python callable (which it is!).

```lisp
CL-USER> (py4cl::pythonize #'car)
"_py4cl_LispCallbackObject(4)"

CL-USER> (pycall (lambda (string) (concatenate 'string string " - from Lisp"))
                 "hello")
"hello - from Lisp"
```

## Slot and Method Lists

Currently, all the python objects are grouped under the class `python-object`. The list of methods 
and slots associated with these objects can be obtained using the following two functions.

### `pyslot-list`
`(pyslot-list python-object &key as-vector)`

```lisp
CL-USER> (defpyfun "Model" "keras")
NIL

CL-USER> (pyslot-list (model))
("__class__" "__delattr__" "__dict__" "__doc__" "__eq__" "__ge__"
 "__getattribute__" "__gt__" "__hash__" "__le__" "__lt__" "__module__" "__ne__"
 "__repr__" "__str__" "__weakref__" "_built" "_expects_training_arg"
 "_inbound_nodes" "_initial_weights" "_is_compiled" "_is_graph_network"
 "_layers" "_losses" "_outbound_nodes" "_per_input_losses" "_per_input_updates"
 "_updates" "_uses_inputs_arg" "built" "input_spec" "inputs" "layers" "losses"
 "name" "non_trainable_weights" "optimizer" "outputs" "state_updates"
 "stateful" "supports_masking" "trainable" "trainable_weights" "updates"
 "uses_learning_phase" "weights")

CL-USER> (pyeval (model) ".inputs")
NIL
```

Optionally, see [pyslot-value](#pyslot-value)

### `pymethod-list`
`(pymethod-list python-object &key as-vector)`

```lisp
CL-USER> (pymethod-list (model))
("__call__" "__class__" "__delattr__" "__dir__" "__eq__" "__format__" "__ge__"
 "__getattribute__" "__getstate__" "__gt__" "__hash__" "__init__"
 "__init_subclass__" "__le__" "__lt__" "__ne__" "__new__" "__reduce__"
 "__reduce_ex__" "__repr__" "__setattr__" "__setstate__" "__sizeof__" "__str__"
 "__subclasshook__" "_add_inbound_node" "_base_init"
 "_check_trainable_weights_consistency" "_get_node_attribute_at_index"
 "_init_graph_network" "_init_subclassed_network" "_make_predict_function"
 "_make_test_function" "_make_train_function" "_node_key" "_set_inputs"
 "_standardize_user_data" "_updated_config" "_uses_dynamic_learning_phase"
 "add_loss" "add_update" "add_weight" "assert_input_compatibility" "build"
 "call" "compile" "compute_mask" "compute_output_shape" "count_params"
 "evaluate" "evaluate_generator" "fit" "fit_generator" "from_config"
 "get_config" "get_input_at" "get_input_mask_at" "get_input_shape_at"
 "get_layer" "get_losses_for" "get_output_at" "get_output_mask_at"
 "get_output_shape_at" "get_updates_for" "get_weights" "load_weights" "predict"
 "predict_generator" "predict_on_batch" "reset_states" "run_internal_graph"
 "save" "save_weights" "set_weights" "summary" "test_on_batch" "to_json"
 "to_yaml" "train_on_batch")
```
Optionally, see [pymethod](#pymethod).

## `chain(*)`
`(chain &rest chain)`

This is inspired by the `chain` in parenscript, discussed in [this issue].

In python it is quite common to apply a chain of method calls, data
member access, and indexing operations to an object. To make this work
smoothly in Lisp, there is the `chain` macro (Thanks to @kat-co and
[[https://common-lisp.net/project/parenscript/reference.html][parenscript]] for the inspiration). This consists of a target object,
followed by a chain of operations to apply.  For example
```lisp
(chain "hello {0}" (format "world") (capitalize)) ; => "Hello world"
```
which is converted to python `return "hello {0}".format("world").capitalize()`.

`chain` has two variants: `chain` is a macro, and `chain*` is a function.

A few examples are as follows:

```lisp
(chain (slice 3) stop) ; => 3
```


Symbols as first argument, or arguments to python methods, are
evaluated, so the following works:
```lisp
(let ((format-str "hello {0}")
      (argument "world"))
 (py4cl:chain format-str (format argument))) ; => "hello world"
```

Arguments to methods are lisp, since only the top level forms in `chain` are treated specially:
```lisp
CL-USER> (chain (slice 3) stop)
3
CL-USER> (let ((format-str "hello {0}")
               (argument "world"))
           (chain* format-str `(format ,argument)))
"hello world"
CL-USER> (chain* "result: {0}" `(format ,(+ 1 2)))
"result: 3"
CL-USER> (chain (aref "hello" 4))
"o"
CL-USER> (chain (aref "hello" (slice 2 4)))
"ll"
CL-USER> (chain (aref #2A((1 2 3) (4 5 6)) (slice 0 2)))
#2A((1 2 3) (4 5 6))
CL-USER> (chain (aref #2A((1 2 3) (4 5 6))  1 (slice 0 2)))
#(4 5)
CL-USER> (pyexec "class TestClass:
      def doThing(self, value = 42):
        return value")
NIL
CL-USER> (chain ("TestClass") ("doThing" :value 31))
31
```

There is also `(setf chain)`:

```lisp
CL-USER> (pyeval 
          (with-remote-object (array (np:zeros '(2 2)))
            (setf (chain* `(aref ,array 0 1)) 1.0
                  (chain* `(aref ,array 1 0)) -1.0)
            array))
#2A((0.0 1.0) (-1.0 0.0))
```

Note that this modifies the value in python, so the above example only
works because =array= is a handle to a python object, rather than an
array which is stored in lisp. The following therefore does not work:

```lisp
CL-USER> (let ((array (np:zeros '(2 2))))
           (setf (chain* `(aref ,array 0 1)) 1.0
                 (chain* `(aref ,array 1 0)) -1.0)
           array)
#2A((0.0 0.0) (0.0 0.0))
```

## `with-remote-objects(*)`
`(with-remote-objects &body body)

If a sequence of python functions and methods are being used to manipulate data,
then data may be passed between python and lisp. This is fine for small amounts
of data, but inefficient for large datasets.

The `with-remote-objects` and `with-remote-objects*` macros provide `unwind-protect` environments
in which all python functions return handles rather than values to lisp. This enables
python functions to be combined without transferring much data.

```lisp
(with-remote-objects (py4cl:python-eval "1+2")) 
; => #S(PY4CL::PYTHON-OBJECT :TYPE "<class 'int'>" :HANDLE 0)
```

`with-remote-objects*` evaluates the last result, instead of merely returning a handle

```lisp
(with-remote-objects* (py4cl:python-eval "1+2")) ; => 3
```

The advantage comes when dealing with large arrays or other datasets:
```lisp
CL-USER> (time (let ((arr (make-array 1000000 
                                      :element-type 'single-float
                                      :initial-element 2.0))) 
                 (np:sum (np:add arr arr))))
;  0.258 seconds of real time
;  8,065,504 bytes consed
4000000.0
CL-USER> (time (with-remote-objects 
                 (let ((arr (make-array 1000000 
                                        :element-type 'single-float
                                        :initial-element 2.0))) 
                   (np:sum (np:add arr arr)))))
;  0.100 seconds of real time
;  4,065,456 bytes consed
4000000.0
```
Note that this requires you to solely use python functions and methods. So, do not expect something like this to work:

```lisp
(with-remote-objects (print (aref (np:ones :shape '(10000000)) 0)))
; Error
```

to work.

Besides this, see [Setting up](#setting-up) for using ram-disk and `numpy-file-format` to
combine lisp and python functions.
.

## `python-getattr`
`(python-getattr object slot-name)`

Lisp structs and class objects can be passed to python, put into data structures and
returned:

```lisp
(defpyfun "dict") ; Makes python dictionaries

(defstruct test-struct 
    x y)

(let ((map (dict :key (make-test-struct :x 1 :y 2))))  ; Make a dictionary, return as hash-map
  ;; Get the struct from the hash-map, and get the Y slot
  (test-struct-y
    (chain* `(aref ,map "key"))))  ; => 2
```


In python this is handled using an object of class `UnknownLispObject`, which
contains a handle. The lisp object is stored in a hash map
`*lisp-objects*`. When the python object is deleted, a message is sent to remove
the object from the hash map.

To enable python to access slots, or call methods on a struct or class, a
handler function needs to be registered. This is done by providing a method 
for generic function `python-getattr`. This function will be called when a
python function attempts to access attributes of an object (`__getattr__`
method).

```lisp
;; Define a class with some slots
(defclass test-class ()
  ((value :initarg :value)))

;; Define a method to handle calls from python
(defmethod python-getattr ((object test-class) slot-name)
  (cond
    ((string= slot-name "value") ; data member
      (slot-value object 'value))
    ((string= slot-name "func")  ; method, return a function
      (lambda (arg) (* 2 arg)))
    (t (call-next-method)))) ; Otherwise go to next method

(let ((instance (make-instance 'test-class :value 21))) 
  ;; Get the value from the slot, call the method
  ;; python: instance.func(instance.value)
  (chain* `((@ ,instance func) (@ ,instance value))))  ; => 42
```
Inheritance then works as usual with CLOS methods:
```lisp
;; Class inheriting from test-class
(defclass child-class (test-class)
  ((other :initarg :other)))

;; Define method which passes to the next method if slot not recognised
(defmethod py4cl:python-getattr ((object child-class) slot-name)
  (cond
    ((string= slot-name "other")
     (slot-value object 'other))
    (t (call-next-method))))

(let ((object (make-instance 'child-class :value 42 :other 3)))
  (list 
    (chain* object 'value) ; Call TEST-CLASS getattr method via CALL-NEXT-METHOD
    (chain* object 'other))) ;=> (42 3)
```

# Testing 

Tests use [clunit](https://github.com/tgutu/clunit), and run on [Travis](https://travis-ci.org/) using [cl-travis](https://github.com/luismbo/cl-travis). Most development
is done under Arch linux with SBCL and Python3. To run the tests
yourself:
```lisp
(asdf:test-system :py4cl)
```
or

```lisp
(ql:quickload :py4cl-tests)
(py4cl1-tests:run)
```




# Type Mapping and Pythonize

Data is passed between python and lisp as text. The python function
`lispify` converts values to a form which can be read by the lisp
reader; the lisp function `pythonize` outputs strings which can be
`eval`'d in python. The following type conversions are done:


```
| Lisp type | Python type   |
|-----------+---------------|
| NIL       | None          |
| integer   | int           |
| ratio     | float         |
| real      | float         |
| complex   | complex float |
| string    | str           |
| hash map  | dict          |
| list      | tuple         |
| vector    | list          |
| array     | NumPy array   |
| symbol    | Symbol class  |
| function  | function      |
```

Note that python does not have all the numerical types which lisp has,
for example rational numbers or complex integers.

Because `pyeval` and `pyexec` evaluate strings as python
expressions, strings passed to them are not escaped or converted as
other types are. To pass a string to python as an argument, call `py4cl::pythonize`

```lisp
CL-USER> (py4cl::pythonize "string")
"\"string\""
CL-USER> (py4cl::pythonize #'identity)
"_py4cl_LispCallbackObject(1)"
CL-USER> (py4cl::pythonize 3.0)
"3.0"
CL-USER> (py4cl::pythonize (model)) ;; keras.Model
"_py4cl_objects[1918]"
```

If python objects cannot be converted into a lisp value, then they are
stored and a handle is returned to lisp. This handle can be used to
manipulate the object, and when it is garbage collected the python
object is also deleted (using the [trivial-garbage](https://common-lisp.net/project/trivial-garbage/) 
package).

# Name Mapping

The arguments passed to `pycall` are parsed as follows: the lisp keywords are converted to their python equivalents. This only entails downcasing the symbol-name of the keywords and replacing hyphens with underscores. If the symbol-name contained capital letters, then, if all the letters are capitals, the symbol-name is downcased; else it stays as it is

```lisp
CL-USER> (pyexec "
def foo(A, b):
  return True")
NIL
CL-USER> (pycall 'foo :*A* 4 :b 3)
NIL
CL-USER> (foo :a 4 :b 3)
; Evaluation aborted on #<PYERROR {100E2AF473}>.
;; unexpected keyword argument 'a'
CL-USER> (foo 4 3)
T
```
Lispfication of python names is done by `defpyfun`, in import-export.lisp. Both `CamelCase` and `joint_words` are converted to `camel-case` and `joint-words`; the actual names of the arguments are substituted:

```lisp
CL-USER> (macroexpand-1 '(defpyfun "foo"))
(DEFUN FOO (&KEY (A 'NIL) (B 'NIL))
  "Python function"
  NIL
  (PYTHON-START-IF-NOT-ALIVE)
  (RAW-PYEVAL "foo" "(" "A" "=" (PY4CL2::PYTHONIZE A) "," "b" "="
              (PY4CL2::PYTHONIZE B) "," ")"))
T
```

The format of the calling expression does depend on the signature of the function.



# What remains?

See [TODO].

# Also check out

## [The Common Lisp Cookbook](http://lispcookbook.github.io/cl-cookbook/)

---

This template was taken from [The Common Lisp Cookbook][tCLC].

[tCLC]: https://github.com/LispCookbook/cl-cookbook
[pyeval]: #expressions-pyeval-rest-args
[limitations]: #limitations-of-this-documentation
[pycall]: #pycall
[TODO]: https://github.com/digikar99/py4cl/blob/master/TODO.org
[Name Mapping]: #name-mapping
