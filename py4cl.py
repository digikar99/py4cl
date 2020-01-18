# Python interface for py4cl
# 
# This code handles messages from lisp, marshals and unmarshals data,
# and defines classes which forward all interactions to lisp.
#
# Should work with python 2.7 or python 3

from __future__ import print_function

import sys
import numbers
import itertools
import inspect
import json
import os
import signal

return_stream = sys.stdout
output_stream = sys.stderr
sys.stdout = sys.stderr

eval_globals = {}
config = {}
def load_config():
    config_file = sys.argv[1] + ".config"
    if os.path.exists(config_file):
        with open(config_file) as conf:
            global config
            config = json.load(conf)
            try:
                eval_globals["_py4cl_config"] = config
            except:
                pass
    else:
        print(".config file not found!")
        eval_globals["_py4cl_config"] = {}
load_config()
        
class Symbol(object):
    """
    A wrapper around a string, representing a Lisp symbol. 
    """
    def __init__(self, name):
        self._name = name
    def __str__(self):
        return self._name
    def __repr__(self):
        return "Symbol("+self._name+")"

class LispCallbackObject (object):
    """
    Represents a lisp function which can be called. 
    
    An object is used rather than a lambda, so that the lifetime
    can be monitoried, and the function removed from a hash map
    """
    def __init__(self, handle):
        """
        handle    A number, used to refer to the object in Lisp
        """
        self.handle = handle

    def __del__(self):
        """
        Delete this object, sending a message to Lisp
        """
        return_stream.write("d")
        send_value(self.handle)

    def __call__(self, *args, **kwargs):
        """
        Call back to Lisp
        
        args   Arguments to be passed to the function
        """
        global return_values
        
        # Convert kwargs into a sequence of ":keyword value" pairs
        # appended to the positional arguments
        allargs = args
        for key, value in kwargs.items():
            allargs += (Symbol(":"+str(key)), value)

        old_return_values = return_values # Save to restore after
        try:
            return_values = 0
            return_stream.write("c")
            send_value((self.handle, allargs))
        finally:
            return_values = old_return_values

        # Wait for a value to be returned.
        # Note that the lisp function may call python before returning
        return message_dispatch_loop()

    
class UnknownLispObject (object):
    """
    Represents an object in Lisp, which could not be converted to Python
    """
    def __init__(self, lisptype, handle):
        """
        lisptype  A string describing the type. Mainly for debugging
        handle    A number, used to refer to the object in Lisp
        """
        self.lisptype = lisptype
        self.handle = handle

    def __del__(self):
        """
        Delete this object, sending a message to Lisp
        """
        return_stream.write("d")
        send_value(self.handle)
        
    def __str__(self):
        return "UnknownLispObject(\""+self.lisptype+"\", "+str(self.handle)+")"

    def __getattr__(self, attr):
        # Check if there is a slot with this name
        return_stream.write("s")
        send_value((self.handle, attr))
        
        # Wait for the result
        return message_dispatch_loop()
        

# Settings

python_to_lisp_type = {
    bool: "BOOLEAN",
    type(None): "NULL",
    int: "INTEGER",
    float: "FLOAT",
    complex: "COMPLEX",
    list: "VECTOR",
    dict: "HASH-TABLE",
    str: "STRING",
}

try:
    python_to_lisp_type[inspect._empty] = "NIL"
except:
    pass

return_values = 0
    
##################################################################
# This code adapted from cl4py
#
# https://github.com/marcoheisig/cl4py
#
# Copyright (c) 2018  Marco Heisig <marco.heisig@fau.de>
#               2019  Ben Dudson <benjamin.dudson@york.ac.uk>

lispifiers = {
    bool       : lambda x: "T" if x else "NIL",
    type(None) : lambda x: "\"None\"",
    int        : str,
    float      : str,
    complex    : lambda x: "#C(" + lispify(x.real) + " " + lispify(x.imag) + ")",
    list       : lambda x: "#(" + " ".join(lispify(elt) for elt in x) + ")",
    tuple      : lambda x: "\"()\"" if len(x)==0 else "(" + " ".join(lispify(elt) for elt in x) + ")",
    # Note: With dict -> hash table, use :test equal so that string keys work as expected
    dict       : lambda x: "#.(let ((table (make-hash-table :test (quote equal)))) " + " ".join("(setf (gethash {} table) {})".format(lispify(key), lispify(value)) for key, value in x.items()) + " table)",
    str        : lambda x: "\"" + x.replace("\\", "\\\\").replace("\"", "\\\"")  + "\"",
    type       : lambda x: python_to_lisp_type[x],
    Symbol     : str,
    UnknownLispObject : lambda x: "#.(py4cl2::lisp-object {})".format(x.handle),
    # there is another lispifier just below
}

# This is used to test if a value is a numeric type
numeric_base_classes = (numbers.Number,)

try:
    # Use NumPy for multi-dimensional arrays
    import numpy

    def load_pickled_ndarray_and_delete(filename):
        arr = numpy.load(filename, allow_pickle = True)
        os.remove(filename)
        return arr

    def lispify_ndarray(obj):
        """Convert a NumPy array to a string which can be read by lisp
        Example:
        array([[1, 2],     => "#2A((1 2) (3 4))"
              [3, 4]])
        """
        if "numpyPickleLowerBound" in config and \
           "numpyPickleLocation" in config and \
           obj.size > config["numpyPickleLowerBound"]:
            numpy_pickle_location = config["numpyPickleLocation"]
            numpy.save(numpy_pickle_location, obj, allow_pickle = True)
            return ("#.(numpy-file-format:load-array \""
                    + numpy_pickle_location + "\")")
        if obj.ndim == 0:
            # Convert to scalar then lispify
            return lispify(numpy.asscalar(obj))
        
        def nested(obj):
            """Turns an array into nested ((1 2) (3 4))"""
            if obj.ndim == 1: 
                return "("+" ".join([lispify(i) for i in obj])+")" 
            return "(" + " ".join([nested(obj[i,...]) for i in range(obj.shape[0])]) + ")"

        return "#{:d}A".format(obj.ndim) + nested(obj)

    # Register the handler to convert Python -> Lisp strings
    lispifiers[numpy.ndarray] = lispify_ndarray

    # Register numeric base class
    numeric_base_classes += (numpy.number,)
except:
    pass

def lispify_handle(obj):
    """
    Store an object in a dictionary, and return a handle
    """
    handle = next(python_handle)
    python_objects[handle] = obj
    return "#.(py4cl2::make-python-object-finalize :type \""+str(type(obj))+"\" :handle "+str(handle)+")"

def lispify(obj):
    """
    Turn a python object into a string which can be parsed by Lisp reader.
    
    If return_values is false then always creates a handle
    """
    if return_values > 0:
        if isinstance(obj, Exception): return str(obj)
        else: return lispify_handle(obj)

    try:
        if isinstance(obj, Exception): return str(obj)
        else: return lispifiers[type(obj)](obj)
    except KeyError:
        # Special handling for numbers. This should catch NumPy types
        # as well as built-in numeric types
        if isinstance(obj, numeric_base_classes):
            return str(obj)
        
        # Another unknown type. Return a handle to a python object
        return lispify_handle(obj)

def generator(function, stop_value):
    temp = None
    while True:
        temp = function()
        if temp == stop_value: break
        yield temp

##################################################################

def recv_string():
    """
    Get a string from the input stream
    """
    length = int(sys.stdin.readline())
    return sys.stdin.read(length)

def recv_value():
    """
    Get a value from the input stream
    Return could be any type
    """
    return eval(recv_string(), eval_globals, eval_locals)

def send_value(value):
    """
    Send a value to stdout as a string, with length of string first
    """
    try:
        # if type(value) == str and return_values > 0:
            # value_str = value # to handle stringified-errors along with remote-objects
        # else:
        value_str = lispify(value)
    except Exception as e:
        # At this point the message type has been sent,
        # so we cannot change to throw an exception/signal condition
        value_str = "Lispify error: " + str(e)
    print(len(value_str), file = return_stream, flush=True)
    return_stream.write(value_str)
    return_stream.flush()

def return_value(value):
    """
    Return value to lisp process, by writing to return_stream
    """
    if isinstance(value, Exception):
        return return_error(value)
    return_stream.write("r")
    return_stream.flush()
    send_value(value)
    
def return_error(error):
    return_stream.write("e")
    send_value(error)

def pythonize(value): # assumes the symbol name is downcased by the lisp process
    """
    Convertes the value (Symbol) to python conventioned strings.
    In particular, replaces "-" with "_"
    """
    return str(value)[1:].replace("-", "_")
        
def message_dispatch_loop():
    """
    Wait for a message, dispatch on the type of message.
    Message types are determined by the first character:

    e  Evaluate an expression (expects string)
    x  Execute a statement (expects string)
    q  Quit
    """
    global return_values  # Controls whether values or handles are returned
    
    while True:
        try:
            # Read command type
            cmd_type = sys.stdin.read(1)
            
            if cmd_type == "e":  # Evaluate an expression
                expr = recv_string()
                # if expr not in cache:
                  # print("Adding " + expr + " to cache")
                  # cache[expr] = eval("lambda : " + expr, eval_globals, eval_locals)
                # result = cache[expr]()
                result = eval(expr, eval_globals, eval_locals)
                return_value(result)
            elif cmd_type == "x": # Execute a statement
                exec(recv_string(), eval_globals, eval_locals)
                return_value(None)
            elif cmd_type == "q":
                exit(0)
            elif cmd_type == "r": # return value from lisp function
                return recv_value()
            elif cmd_type == "O":  # Return only handles
                return_values += 1
            elif cmd_type == "o":  # Return values when possible (default)
                return_values -= 1
            else:
                return_error("Unknown message type \"{0}\"".format(cmd_type))
        except KeyboardInterrupt as e: # to catch SIGINT
            # output_stream.write("Python interrupted!\n")
            return_value(None)
        except Exception as e:
            return_error(e)


# Store for python objects which cannot be translated to Lisp objects
python_objects = {}
python_handle = itertools.count(0)
 
# Make callback function accessible to evaluation
eval_globals["_py4cl_LispCallbackObject"] = LispCallbackObject
eval_globals["_py4cl_Symbol"] = Symbol
eval_globals["_py4cl_UnknownLispObject"] = UnknownLispObject
eval_globals["_py4cl_objects"] = python_objects
eval_globals["_py4cl_generator"] = generator
# These store the environment used when eval-ing strings from Lisp
eval_globals["_py4cl_config"] = config
eval_globals["_py4cl_load_config"] = load_config
try:
    # NumPy is used for Lisp -> Python conversion of multidimensional arrays
    eval_globals["_py4cl_numpy"] = numpy
    eval_globals["_py4cl_load_pickled_ndarray_and_delete"] \
      = load_pickled_ndarray_and_delete
except:
    pass

eval_locals = {}
# Handle fractions (RATIO type)
# Lisp will pass strings containing "_py4cl_fraction(n,d)"
# where n and d are integers.
try:
    import fractions
    eval_globals["_py4cl_fraction"] = fractions.Fraction
    
    # Turn a Fraction into a Lisp RATIO
    lispifiers[fractions.Fraction] = str
except:
    # In python2, ensure that fractions are converted to floats
    eval_globals["_py4cl_fraction"] = lambda a,b : float(a)/b

async_results = {}  # Store for function results. Might be Exception
async_handle = itertools.count(0) # Running counter

# Main loop
message_dispatch_loop()
