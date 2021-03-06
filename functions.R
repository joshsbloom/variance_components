# Tutorial / general purpose mixed model solver 
# y named(!) phenotype vector (n)
# B named list of covariance structures (m x m matrices)
# X a incidence matrix for fixed effects (n x p fixed effects)
# Z a incidence matrix for random effects (n x m) 
# Ze a incidence matrix for random effects for error term only
# reps  (T or F, are there replicates??)
# alg derivative based algorithm ('ai' = average information, 'fs' = fisher scoring (default, most numerically stable), or 'nr' = newton-rhapson (fastest to slowest), sqrt  )
# conv.val value for convergence
# Var vector of initialization values for variance components
# positiveVCs (should estimates of VCs be constrained to be positive)
# Returns a list:
# ...$Var = VC estimates
# ...$invI = fisher information matrix
#  sqrt(diag(...$invI)) = SE of VC estimates
# ...$W = Vinverse
# ...$Bhat = fixed effects
# ...$llik = REML log-likelihood
calcMM = function(y, B=NULL,X=NULL, Z=NULL, Ze=NULL, reps=FALSE,
                     alg='fs', conv.val=1e-6, Var=NULL,positiveVCs=FALSE){
    strain.names=(names(y))
    unique.sn=unique(strain.names)
    n.to.m=match(strain.names, unique.sn)

    strain.ind  = seq_along(strain.names)
    strain.cnt  = length(unique.sn)
    #for constructing Strain Variance component
    Strain      = Matrix(diag(strain.cnt), sparse=T)

    # If B is NULL then add a covariance term that is the identity matix - will then calculate effect of strain (broad-sense heritability)
    if(is.null(B)) { B=list(Strain=Strain);  } else{
        if (reps) { B=c(B, list(Strain=Strain))  } }    
    # If Z is null and there are no replicates this will make Z a diagonal incidence matrix, otherwise this constructs an incidence matrix based on strain names
    if(is.null(Z)) {   Z=Matrix(0, length(y), strain.cnt,sparse=T);   Z[cbind(strain.ind, n.to.m)]=1 }
    # If X is null assume one fixed effect of population mean
    if(is.null(X) ) {  X=model.matrix(y~1)}
    # If Ze is null assume no error structure
    if(is.null(Ze)) {  Ze=Matrix((diag(length(y))),sparse=T) }

    #number of terms in the structured covariance
    VC.names=paste('sigma', c(names(B), 'E'), sep='')
    N.s.c=length(B)
    Vcmp.cnt=N.s.c+1
    # starting values for VC estimates as 1 / (#of VCs including residual error term)
    if(is.null(Var) ) { Var=rep(1/Vcmp.cnt, Vcmp.cnt) }
    I = matrix(0, ncol= Vcmp.cnt, nrow= Vcmp.cnt)
	s = matrix(0, ncol=1, nrow= Vcmp.cnt)
    
    diffs=rep(10,  Vcmp.cnt)
    
    # second derivatives of V with respect to the variance components (Lynch and Walsh 27.15)
    VV = list()
    for(i in 1:N.s.c) {
              VV[[i]]=Z %*% tcrossprod(B[[i]],Z)  
    }
    VV[[ Vcmp.cnt ]]=Ze 

    i = 0
    # while the differences haven't converged 
    while ( sum(ifelse(diffs<conv.val, TRUE,FALSE)) <  Vcmp.cnt ) { 
		i = i + 1
        V=matrix(0,length(y), length(y))
	    for( vcs in 1:length(VV)) {  V=V+(VV[[vcs]]*Var[vcs]) }
        print('Inverting V')
        Vinv = solve(V)
        print('Done inverting V')
        tXVinvX=t(X) %*% as.matrix(Vinv) %*% X
        print('Done inverting t(X)%*%Vinv%*%X')
        #sx=svd(tXVinvX)
        #inv.tXVinvX=sx$v %*% diag(1/sx$d) %*% t(sx$u) #  Xinv = V 1/D U'
        inv.tXVinvX = solve(tXVinvX)
        #inv.tXVinvX =pinv(as.matrix(tXVinvX))
        itv = inv.tXVinvX %*% t(X)%*%Vinv
        P = Vinv - Vinv %*% X %*% itv 

        #algorithm choices
        if(alg=='fs') {print("Fisher scoring algorithm: calculating expected VC Hessian") }
        if(alg=='nr') {print("Netwon rhapson algorithm: calculating observed VC Hessian") }
        if(alg=='ai') {print("Average information algorithm: calculating avg of expected and observed VC Hessians") }
        
        for(ii in 1:Vcmp.cnt) {
           for(jj in ii:Vcmp.cnt) {
                 if (alg=='fs') {    I[ii,jj]= 0.5*sum(diag( ((P%*%VV[[ii]]) %*%P )%*%VV[[jj]])) }
                 if (alg=='nr') {    I[ii,jj]=-0.5*sum(diag(P%*%VV[[ii]]%*%P%*%VV[[jj]])) + (t(y)%*%P%*%VV[[ii]]%*%P%*%VV[[jj]]%*%P%*%y)[1,1] }
                 if (alg=='ai') {    I[ii,jj]= 0.5*( t(y)%*%P%*%VV[[ii]]%*%P%*%VV[[jj]]%*%P%*%y)[1,1]  } 
                 print(paste(ii, jj))
                 I[jj,ii]=I[ii,jj]
           }
           s[ii,1]= -0.5*sum(diag(P%*%VV[[ii]])) + .5*(t(y)%*%P%*%VV[[ii]]%*%P%*%y )[1,1] 
        }
        invI = solve(I)
        print(invI)
        print(s) 
        newVar = Var + invI%*%s
        # uncomment the line below if you wanted to constrain VC estimates to be positive
        if(positiveVCs) {     newVar[newVar<0]=2.6e-9 }

        for(d in 1:length(diffs)) { diffs[d]=abs(Var[d] - newVar[d]) }
		Var = newVar
        
        cat('\n')
        cat("iteration ", i, '\n')
        cat(VC.names, '\n')
        cat(Var, '\n')
        # hard stop on number of iterations 
        if(i>100) { stop(" give up, never going to converge ... or try changing specifying starting values in Var" ) } 
        Bhat= itv %*% y
        cat("Fixed Effects, Bhat = ", as.matrix(Bhat), '\n')
#        det.tXVinvX=determinant(tXVinvX, logarithm=TRUE)
#        det.tXVinvX=det.tXVinvX$modulus*det.tXVinvX$sign
#        det.V =determinant(V, logarithm=TRUE)
#        det.V=det.V$modulus*det.V$sign
#        LL = -.5 * (det.tXVinvX + det.V + log(t(y) %*% P %*% y) )
#        cat("Log Likelihood = " , as.matrix(LL), '\n')
        cat("VC convergence vals", '\n')
        cat(diffs, '\n')
	}
    	cat('\n')
	return(list(Var=Var, invI=invI, W=Vinv, Bhat=Bhat)) #, llik=LL))
}

#calculate strain blups (see calcMM for variable definitions)
calc.BLUPS= function(G,Z,Vinv,y,X,B ){    ((G%*%t(Z)) %*% Vinv) %*%( y - X%*%B)     }



#these two functions are for using Eskin 2008 SVD trick for speedup when genotype matrix is 
# super optimized for one VC and fixed effects ~1000X speedup by precomputing eigen decomp
m.S=function (y, K = NULL, bounds = c(1e-09, 1e+09), theta=NULL, Q=NULL, X=NULL ) 
{
    n <- length(y)
    y <- matrix(y, n, 1)
    if(is.null(X) ) {  p <- 1    } else { p = ncol(X) }
    Z <- diag(n)
    m <- ncol(Z)
       
    omega <- crossprod(Q, y)
    omega.sq <- omega^2
    
    f.REML <- function(lambda, n.p, theta, omega.sq) {
        n.p * log(sum(omega.sq/(theta + lambda))) + sum(log(theta + lambda))
    }
    soln <- optimize(f.REML, interval = bounds, n - p, theta,  omega.sq)
    lambda.opt <- soln$minimum
    
    df <- n - p
    Vu.opt <- sum(omega.sq/(theta + lambda.opt))/df
    Ve.opt <- lambda.opt * Vu.opt
    VCs=c(Vu.opt, Ve.opt)
    return(VCs)
}

doEigenA_forMM=function(A ,X=NULL ) {
        n=nrow(A)
        if(is.null(X) ) {  X = matrix(rep(1, n), n, 1); p=1 } else {p=ncol(X) }
        XtX = crossprod(X, X)
        XtXinv = solve(XtX)
        S = diag(n) - tcrossprod(X %*% XtXinv, X)
        SHbS = S %*% A %*% S
        SHbS.system = eigen(SHbS, symmetric = TRUE)
        theta = SHbS.system$values[1:(n - p)] 
        Q = SHbS.system$vectors[, 1:(n - p)]
        return(list(theta=theta, Q=Q))
        }
#---------------------------------------------------------------------------------------------------------------



#simple phenotype simulator
# G is (n x M) matrix (n = individuals, M = markers)
# h2 is additive variance 
# nadditive is number of markers with effects (here randomly + or -)
# nsims is number of simulated phenotypes
simPhenotypes=function(G, h2, nadditive, nsims) {
    nsample  =nrow(G)
    nmarker  =ncol(G)

    simY=replicate(nsims, {
        #total number of additive loci
        a.eff  = rep(0,nsample)
        #markers with effects
        add.qtl.ind  = sort(sample(nmarker, nadditive))
        add.qtl.sign = sample(ifelse(runif(nadditive)>.5,1,-1),replace=T)

        for(i in 1:nadditive){ a.eff=a.eff+add.qtl.sign[i]*G[,add.qtl.ind[i]] }
        a.eff=scale(a.eff)
        g=sqrt(h2)*a.eff 
        y=as.vector(g+rnorm(nrow(G),mean=0,sd=sqrt((1-h2)/h2*var(g))))
        return(y)
    })
    #for tutorial code name the strains
    rownames(simY)=seq_along(simY[,1])
    return(simY)
}


