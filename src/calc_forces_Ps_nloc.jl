function calc_forces_Ps_nloc( Ham, psiks )
    F_Ps_nloc = zeros(Float64, 3, Ham.atoms.Natoms)
    calc_forces_Ps_nloc!( Ham, psiks, F_Ps_nloc )
    return F_Ps_nloc
end

function calc_forces_Ps_nloc!(
    Ham::Hamiltonian,
    psiks::BlochWavefunc,
    F_Ps_nloc::Array{Float64,2}
)
    calc_forces_Ps_nloc!( Ham.atoms, Ham.pw, Ham.pspots, Ham.electrons, Ham.pspotNL, psiks, F_Ps_nloc)
    return
end

function calc_forces_Ps_nloc!(
    atoms::Atoms,    
    pw::PWGrid,
    pspots::Array{PsPot_GTH,1},
    electrons::Electrons,
    pspotNL::PsPotNL,
    psiks::BlochWavefunc,
    F_Ps_nloc::Array{Float64,2}
)

    Nstates = electrons.Nstates
    Focc = electrons.Focc
    Natoms = atoms.Natoms
    atm2species = atoms.atm2species
    prj2beta = pspotNL.prj2beta
    Nkpt = pw.gvecw.kpoints.Nkpt
    wk = pw.gvecw.kpoints.wk
    NbetaNL = pspotNL.NbetaNL
    Nspin = electrons.Nspin

    if NbetaNL == 0
        return F_Ps_nloc
    end

    betaNL_psi = zeros(ComplexF64,Nstates,NbetaNL)
    dbetaNL_psi = zeros(ComplexF64,3,Nstates,NbetaNL)

    dbetaNL = calc_dbetaNL(atoms, pw, pspots, pspotNL)

    for ispin = 1:Nspin, ik = 1:Nkpt

        ikspin = ik + (ispin - 1)*Nkpt
        psi = psiks[ikspin]
        betaNL_psi = calc_betaNL_psi( ik, pspotNL.betaNL, psi )
        dbetaNL_psi = calc_dbetaNL_psi( ik, dbetaNL, psi )
        
        for ist = 1:Nstates
            for ia = 1:Natoms
                isp = atm2species[ia]
                psp = pspots[isp]
                for l = 0:psp.lmax
                for m = -l:l
                for iprj = 1:psp.Nproj_l[l+1]
                for jprj = 1:psp.Nproj_l[l+1]
                    ibeta = prj2beta[iprj,ia,l+1,m+psp.lmax+1]
                    jbeta = prj2beta[jprj,ia,l+1,m+psp.lmax+1]
                    hij = psp.h[l+1,iprj,jprj]
                    fnl1 = hij*conj(betaNL_psi[ist,ibeta])*dbetaNL_psi[:,ist,jbeta]
                    F_Ps_nloc[:,ia] = F_Ps_nloc[:,ia] + 2*wk[ik]*Focc[ist,ikspin]*real(fnl1)
                end
                end
                end # m
                end # l
            end
        end
    end

    return
end



function calc_dbetaNL(
    atoms::Atoms,
    pw::PWGrid,
    pspots::Array{PsPot_GTH,1},
    pspotNL::PsPotNL
)

    Natoms = atoms.Natoms
    atm2species = atoms.atm2species
    atpos = atoms.positions
    kpoints = pw.gvecw.kpoints
    Nkpt = kpoints.Nkpt
    k = kpoints.k
    Ngw = pw.gvecw.Ngw
    Ngwx = pw.gvecw.Ngwx
    NbetaNL = pspotNL.NbetaNL
    dbetaNL = zeros( ComplexF64, 3, Ngwx, NbetaNL, Nkpt )
    G = pw.gvec.G
    g = zeros(3)
    
    for ik = 1:Nkpt
        ibeta = 0
        for ia = 1:Natoms
            isp = atm2species[ia]
            psp = pspots[isp]
            for l = 0:psp.lmax
            for m = -l:l
            for iprj = 1:psp.Nproj_l[l+1]
                ibeta = ibeta + 1
                idx_gw2g = pw.gvecw.idx_gw2g[ik]
                for igk = 1:Ngw[ik]
                    ig = idx_gw2g[igk]
                    g[1] = G[1,ig] + k[1,ik]
                    g[2] = G[2,ig] + k[2,ik]
                    g[3] = G[3,ig] + k[3,ik]
                    Gm = norm(g)
                    GX = atpos[1,ia]*g[1] + atpos[2,ia]*g[2] + atpos[3,ia]*g[3]
                    Sf = cos(GX) - im*sin(GX)
                    dbetaNL[:,igk,ibeta,ik] =
                    (-1.0*im)^l * Ylm_real(l,m,g)*eval_proj_G(psp,l,iprj,Gm,pw.CellVolume)*Sf*im*g[:]
                    #Ylm_real(l,m,g)*eval_proj_G(psp,l,iprj,Gm,pw.CellVolume)*Sf*im*g[:]
                end
            end
            end
            end
        end
    end  # kpoints

    return dbetaNL
end

function calc_dbetaNL_psi( ik::Int64, dbetaNL::Array{ComplexF64,4}, psi::Array{ComplexF64,2} )
    Nstates = size(psi)[2]
    NbetaNL = size(dbetaNL)[3]  # NOTE: 3rd dimension
    Ngw_ik = size(psi)[1]
    dbetaNL_psi = zeros( ComplexF64, 3, Nstates, NbetaNL )
    for ist = 1:Nstates
        for ibeta = 1:NbetaNL
            dbetaNL_psi[1,ist,ibeta] = dot( dbetaNL[1,1:Ngw_ik,ibeta,ik], psi[:,ist] )
            dbetaNL_psi[2,ist,ibeta] = dot( dbetaNL[2,1:Ngw_ik,ibeta,ik], psi[:,ist] )
            dbetaNL_psi[3,ist,ibeta] = dot( dbetaNL[3,1:Ngw_ik,ibeta,ik], psi[:,ist] )
        end
    end
    return dbetaNL_psi
end