"""
Find eigenvalues and eigenvectors of `Ham::Hamiltonian` using `X0`
as initial guess for eigenvectors using
locally-optimal block preconditioned conjugate gradient method
of Knyazev.

**IMPORTANT** `X0` must be orthonormalized before.
"""
function diag_LOBPCG( Ham::Hamiltonian, X0::Array{ComplexF64,2};
                      tol=1e-5, NiterMax=100, verbose=false,
                      verbose_last=false, Nstates_conv=0 )

    pw = Ham.pw
    # get size info
    Nbasis = size(X0)[1]
    Nstates = size(X0)[2]

    if Nstates_conv == 0
        Nstates_conv = Nstates
    end

    X = copy(X0)

    HX = op_H( Ham, X )

    nconv = 0
    iter = 1
    resnrm = ones(Nstates,1)

    P = zeros(ComplexF64,Nbasis,Nstates)
    HP = zeros(ComplexF64,Nbasis,Nstates)

    evals = zeros(Float64,Nstates)
    devals = ones(Float64,Nstates)
    evals_old = copy(evals)

    #tfudge = 1e5
    SMALL = 10.0*eps()

    IS_CONVERGED = false
    
    for iter = 1:NiterMax

        # Rayleigh quotient
        XHX = Hermitian(X'*HX)
        evals = eigvals(XHX)

        devals = abs.( evals - evals_old )
        evals_old = copy(evals)
        
        # Residuals
        R = HX - X*XHX
        for j = 1:Nstates
            resnrm[j] = norm( R[:,j] )
        end

        nconv = length( findall( devals .< tol ) )
        
        ilock = findall( devals .<= SMALL )
        iact  = findall( devals .> SMALL )

        Nlock = length(ilock)
        Nact = length(iact)

        if verbose
            @printf("LOBPCG iter = %8d, nconv=%d\n", iter, nconv)
            for ist = 1:Nstates
                @printf("evals[%d] = %18.10f, devals = %18.10e\n", ist, evals[ist], devals[ist] )
            end
            println("Nlock = ", Nlock, " Nact = ", Nact)
        end

        # Check for convergence
        if nconv >= Nstates_conv
            IS_CONVERGED = true
            if verbose || verbose_last
                @printf("LOBPCG convergence: nconv = %d in %d iterations\n", nconv, iter)
            end
            break
        end

        # apply preconditioner
        W = Kprec( Ham.ik, pw, R )

        if Nlock > 0
            Xlock = X[:,ilock]
            Ylock = Kprec( Ham.ik, pw, Xlock )
            Slock = Xlock'*Xlock
            for j = 1:Nact
                W[:,iact[j]] = W[:,iact[j]] - Ylock*( Slock\( Xlock'*W[:,iact[j]] ) )
             end
             #
             X[:,iact] = X[:,iact] - Xlock*(Xlock'*X[:,iact])
             W[:,iact] = W[:,iact] - Xlock*(Xlock'*W[:,iact])
             #
             HX[:,iact] = op_H( Ham, X[:,iact] )
             HW = op_H( Ham, W[:,iact] )
             #
             HX[:,iact] = HX[:,iact] - Xlock*( Xlock'*HX[:,iact] )
             HW = HW - Xlock*(Xlock'*HW)
             #
             C = W[:,iact]'*W[:,iact] #C = (C+C')/2;
             R = (cholesky(Hermitian(C))).U
             W[:,iact] = W[:,iact]/R
             HW = HW/R
             #
             Q  = [X[:,iact] W[:,iact]]
             HQ = [HX[:,iact] HW]

             T = Hermitian(Q'*(HQ))
             G = Hermitian(Q'*Q)
             sd, S = eigen( T, G ) # evals, evecs

             U = S[:,1:Nact]
             Xact = Q*U;
             X = [Xlock Xact]
             T = Hermitian( X'*op_H(Ham,X) ) #; T = (T+T')/2;
             evalT, evecsT = eigen(T);

             X = X*evecsT
             HX = op_H(Ham, X)

        else
            # nlock == 0
            HW = op_H( Ham, W )
            #
            C  = W'*W
            #C = 0.5*( C + C' )
            #
            R  = (cholesky(Hermitian(C))).U
            W  = W/R
            HW = HW/R
            #
            Q  = [X W]
            HQ = [HX HW]
            if iter > 1
                Q  = [Q P]
                HQ = [HQ HP]
            end

            T = Hermitian(Q'*(HQ))
            G = Hermitian(Q'*Q)
            sd, S = eigen(T, G) # evals, evecs
            #
            U = S[:,1:Nstates]
            X = Q*U
            HX = HQ*U
            if iter > 1
                set2 = Nstates+1:2*Nstates
                set3 = 2*Nstates+1:3*Nstates
                P  = W*U[set2,:] + P*U[set3,:]
                HP = HW*U[set2,:] + HP*U[set3,:]
                C = P'*P
                #C = 0.5*(C + C')
                R = (cholesky(Hermitian(C))).U
                P = P/R
                HP = HP/R
            else
                P  = copy(W)
                HP = copy(HW)
            end

        end  # if nlock 



        iter = iter + 1
    end

    if !IS_CONVERGED
        @printf("\nWARNING: LOBPCG is not converged after %d iterations\n", NiterMax)
    end

    S = X'*HX
    S = Hermitian(0.5*(S+S'))
    evals, Q = eigen(S)
    X = X*Q
    if verbose_last || verbose
        @printf("\nEigenvalues from diag_LOBPCG:\n\n")
        for ist = 1:Nstates
            @printf("evals[%d] = %18.10f, devals = %18.10e\n", ist, evals[ist], devals[ist] )
        end
    end
    return evals, X
end