library(ebal)
# Covariate Balancing Propensity Score
# This simple script uses Base R's `optim` to solve a variant of (7.10) from
# http://web.stanford.edu/~swager/stats361.pdf to target ATT weights.
# (see https://arxiv.org/abs/1601.05890 for details)
# Input:
#   X: nXp numeric covariate matrix
#   W: binary treatment assignment vector
#   intercept: whether to include an intercept in logistic model, default is TRUE.
#   θ.init: optional starting values for theta.
#   method: method argument passed to `optim`.
#   control: control argument passed to `optim`.
#   λ: optional ridge penalty (remember to scale X's appropriately if used)
# Output:
#   theta.hat: estimated thetas
#   weights.0: IPW weights for control
#   convergence: optim's convergence status. 0=success.
#   balance condition: the LHS and RHS of the balance condition.

cbps_att = function(
    X, W,
    intercept = TRUE,
    theta.init = NULL, method = "BFGS",
    control = list(), lam = NULL) {
  if (!all(W %in% c(0, 1))) stop("W should be a binary vector.")
  if (!is.numeric(X) || nrow(X) != length(W) || is.null(dim(X)) || anyNA(X)) {
    stop("X should be a numeric matrix with nrows = length(W).")
  }
  .Xtheta = NULL
  # ATT balance constraint is:
  # 1/n1 \sum_{W_i = 0} e(x)/(1-e(x)) Xi = 1/n1 \sum_{Wi=1} Xi,
  # which gives loss function
  # (1 - W)exp(theta * X) - W * theta * X
  .objective = \(θ, X, W0.idx, W1.idx, λ) {
    .Xθ <<- X %*% θ
    (sum(exp(.Xθ[W0.idx, ])) - sum(.Xθ[W1.idx, ])) / length(W1.idx) + sum(λ * θ^2)
  }
  .objective.gradient = \(θ, X0, Xsum1, W0.idx, n, λ) {
    (colSums(X0 * exp(.Xθ[W0.idx, ])) - Xsum1) / n + 2 * λ * θ
  }
  if (is.null(lam)) λ = rep(0, ncol(X))
  if (intercept) {
    X = cbind(1, X)
    λ = c(0, λ)
  }
  W1.idx = which(W == 1); W0.idx = which(W == 0)
  if (is.null(theta.init)) {
    # Use "naive" logistic starting values
    idx.small = c(W1.idx, sample(W0.idx, length(W1.idx)))
    glm = glm.fit(X[idx.small, ], W[idx.small], family = binomial())
    θ.init = glm$coefficients
    # update the intercept, (7) in https://gking.harvard.edu/files/0s.pdf
    if (intercept) {
      ρ = mean(W)
      θ.init[1] = θ.init[1] - log((1 - ρ) / ρ) * length(idx.small) / sum(W)
    }
  }
  X0 = X[W0.idx, ]
  Xsum1 = colSums(X[W1.idx, ])
  res = optim(
    par = θ.init,
    fn = \(z) .objective(z, X, W0.idx, W1.idx, λ),
    gr = \(z) .objective.gradient(z, X0, Xsum1, W0.idx, nrow(X), λ),
    method = method,
    lower = -Inf,
    upper = Inf,
    control = control,
    hessian = FALSE
  )
  θ.hat = res$par
  weights.0 = exp(X %*% θ.hat)[, ]
  LHS = colSums((1 - W) * X * weights.0) / sum(W == 1)
  RHS = colSums(W * X) / sum(W == 1)
  sd.W1 = apply(X[W1.idx, ], 2, sd)
  sd.W1[sd.W1 == 0] = 1
  sd.W = apply(X, 2, sd)
  sd.W[sd.W == 0] = 1
  mean.diff = colMeans(X[W1.idx, ]) -
    apply(X[W0.idx, ], 2, \(x) weighted.mean(x, weights.0[W0.idx]))
  balance.std = mean.diff / sd.W1
  balance.std.pre = (colMeans(X[W1.idx, ]) - colMeans(X[W0.idx, ])) / sd.W1
  balance.std.all = mean.diff / sd.W
  balance.std.pre.all = (colMeans(X[W1.idx, ]) - colMeans(X[W0.idx, ])) / sd.W
  list(
    θ.hat = θ.hat,
    weights.0 = weights.0,
    convergence = res$convergence,
    balance.condition = cbind(LHS = LHS, RHS = RHS),
    balance.std = if (intercept) balance.std[-1] else balance.std,
    balance.std.pre = if (intercept) balance.std.pre[-1] else balance.std.pre,
    balance.std.all = if (intercept) balance.std.all[-1] else balance.std.all,
    balance.std.pre.all = if (intercept) balance.std.pre.all[-1] else balance.std.pre.all
  )
}

# %%
library(LalRUtils)
data(lalonde.psid)
df = setDT(lalonde.psid)
yn = 're78'; wn = 'treat'; xn = setdiff(colnames(df), c(yn, wn))
y = df[[yn]]; w = df[[wn]]; X = df[, ..xn] %>% as.matrix

# %%
ebwt = ebalance(w, X)$w
mean(y[w == 1]) - weighted.mean(y[w == 0], ebwt)
# %% should be the same modulo optimization issues
cbpswt = cbps_att(X, w)
cbpw = cbpswt$weights.0[w == 0]
mean(y[w == 1]) - weighted.mean(y[w == 0], cbpw)
# %%
