>This is a fork of bendudson/py4cl.

# Github Pages

Detailed documentation is available on [github-pages](https://digikar99.github.io/py4cl2/) (could be a bit outdated).

## For MacOS Users

If you have bash 3.2 please upgrade it to a [more recent version](https://www.shell-tips.com/mac/upgrade-bash/#gsc.tab=0).

# Releases

Check the [Releases](https://github.com/digikar99/py4cl2/releases) section. That said, if you are looking for stability, look at py4cl and not py4cl2, at least not in 2021. You may use py4cl2 on use-and-throw projects, or use it without using "edgy" features (not yet classified).

# Contribution and PRs

Please test using [py4cl2-tests](https://github.com/digikar99/py4cl2-tests).

# Quick Demonstration

<img margin="auto" width="75%" src="./docs/readme_slime.png"></img>

```lisp
(ql:quickload :py4cl2 :silent t)

(py4cl2:defpymodule "numpy" nil :lisp-package "NP")
(py4cl2:defpymodule "scipy.integrate" nil :lisp-package "INTEGRATE")

;; Integrate some ODEs
(defparameter *data*
  (integrate:odeint 
   :func (lambda (y time) 
           (list (aref y 1)       ; dy[0]/dt = y[1]
                 (- (aref y 0)))) ; dy[1]/dt = -y[0]
   :y-0 #(1.0 0.0)   ; Initial state
   :t (np:linspace :start 0.0 :stop (* 2 pi) :num 20)))
                                        ; Vector of times

; (array-dimensions *data*) => (20 2)

;; Make a plot, save and show it in a window
(py4cl2:defpymodule "matplotlib.pyplot" nil :lisp-package "PLT")

(plt:plot *data*)
(plt:xlabel :xlabel "Time")
(plt:savefig "result.pdf")
(plt:show)
```

<img margin="auto" width="75%" src="./docs/readme_matplotlib.png"></img>

Great thanks to [Ben Dudson](https://github.com/bendudson) for starting this project, and documenting it enough to make it more-buildable!

