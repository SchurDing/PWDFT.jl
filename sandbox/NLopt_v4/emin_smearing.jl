function dot_ElecGradient( v1::ElecGradient, v2::ElecGradient )
    Nkspin = length(v1.psiks)
    ss = 0.0
    for i in 1:Nkspin
        ss = ss + 2.0*real( dot(v1.psiks[i], v2.psiks[i]) )
        ss = ss + real( dot(v1.Haux[i], v2.Haux[i]) ) # no factor of 2
    end
    return ss
end

function dot_ElecGradient_v2( v1::ElecGradient, v2::ElecGradient )
    Nkspin = length(v1.psiks)
    ss = 0.0
    ss_Haux = 0.0
    for i in 1:Nkspin
        ss = ss + 2.0*real( dot(v1.psiks[i], v2.psiks[i]) )
        ss_Haux = ss_Haux + real( dot(v1.Haux[i], v2.Haux[i]) ) # no factor of 2
    end
    return ss, ss_Haux
end

function compute!(
    Ham::Hamiltonian,
    evars::ElecVars,
    g::ElecGradient, Kg::ElecGradient, kT::Float64,
    rotPrevCinv, rotPrev
)

    Etot = calc_energies_grad!( Ham, evars, g, Kg, kT )

    Nkspin = length(evars.psiks)

    for i in 1:Nkspin
        g.psiks[i] = g.psiks[i] * rotPrevCinv[i]
        Kg.psiks[i] = Kg.psiks[i] * rotPrevCinv[i]
        g.Haux[i] = rotPrev[i] * g.Haux[i] * rotPrev[i]'
        Kg.Haux[i] = rotPrev[i] * Kg.Haux[i] * rotPrev[i]'
    end

    # No caching is done (for SubspaceRotationAdjutst)

    return Etot

end

function do_step!(
    α::Float64, evars::ElecVars, d::ElecGradient,
    rotPrev, rotPrevC, rotPrevCinv
)
    do_step!(α, α, evars, d, rotPrev, rotPrevC, rotPrevCinv)
    return
end

function do_step!(
    α::Float64, α_Haux::Float64, evars::ElecVars, d::ElecGradient,
    rotPrev, rotPrevC, rotPrevCinv
)
    
    Nkspin = length(evars.psiks)
    Nstates = size(evars.psiks[1],2)
    
    Haux = zeros(ComplexF64,Nstates,Nstates)
    rot = zeros(ComplexF64,Nstates,Nstates)
    rotC = zeros(ComplexF64,Nstates,Nstates)

    for i in 1:Nkspin
        evars.psiks[i] = evars.psiks[i] + α*d.psiks[i]*rotPrevC[i]

        # Haux fillings:
        Haux = diagm( 0 => evars.Haux_eigs[:,i] )
        
        #axpy(alpha, rotExists ? dagger(rotPrev[q])*dir.Haux[q]*rotPrev[q] : dir.Haux[q], Haux);
        Haux = Haux + α_Haux*( rotPrev[i]' * d.Haux[i] * rotPrev[i] )
        
        #Haux.diagonalize(rot, eVars.Haux_eigs[q]); //rotation chosen to diagonalize auxiliary matrix
        #evals, evecs = eigen(Haux)
        #println("evals = ", evals)
        evars.Haux_eigs[:,i], rot = eigen(Hermitian(Haux)) # need to symmetrize?
 
        #rotC = rot
        #eVars.orthonormalize(q, &rotC);
        Udagger = inv( sqrt( evars.psiks[i]' * evars.psiks[i] ) )
        rotC = Udagger*rot
        evars.psiks[i] = evars.psiks[i]*rotC
        
        rotPrev[i] = rotPrev[i] * rot
        rotPrevC[i] = rotPrevC[i] * rotC
        rotPrevCinv[i] = inv(rotC) * rotPrevCinv[i]

    end
    
    return 
end

function constrain_search_dir!( d::ElecGradient, evars::ElecVars )
    Nkspin = length(evars.psiks)
    for i in 1:Nkspin
        d.psiks[i] = d.psiks[i] - evars.psiks[i] * ( evars.psiks[i]' * d.psiks[i] )
    end
    return
end
