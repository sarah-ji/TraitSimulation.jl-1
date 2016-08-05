module GWASSimulation

export Simulation, simulate

using SnpArrays
using Distributions

"""
"""
type Simulation
end

"""
"""
function simulate(
    genotypes::SnpData,
    trait_type::Union{Symbol, NTuple{2, Symbol}},
    causal_snps::Union{Dict{AbstractString, Float64},
      NTuple{2, Dict{AbstractString, Float64}}},
    hsq::Union{Float64, NTuple{2, Float64}};
    rep::Int64 = 1,
    missing_rate::Union{Float64, NTuple{2, Float64}} = 0.0,
    prevalence::Union{Float64, NTuple{2, Float64}} = 0.0,
    trait_cor::Float64 = 0.0,
    ncc::Union{NTuple{2, Int64}, NTuple{4, Int64}} = (0,0)
  )

  # simulate a single quantitative trait
  if (typeof(trait_type) == Symbol && trait_type == :q)
    return simulate_liability(genotypes, causal_snps, hsq, rep,
      missing_rate)
  end

  # simulate a single binary (case-control) trait
  if (typeof(trait_type) == Symbol && trait_type == :b)
    return simulate_case_control(genotypes, causal_snps, hsq, rep,
      prevalence, ncc)
  end

  # simulate a pair of correlated quantitative traits
  if (typeof(trait_type) == NTuple{2, Symbol} && trait_type == (:q, :q))
    return simulate_liability(genotypes, causal_snps, hsq, trait_cor,
      rep, missing_rate)
  end

  # simulate a quantitative trait and a binary (case-control) trait

  # simulate a pair of binary (case-control) traits

end # end function simulate

"""
"""
function get_effect_size_vector(snpid, causal_snps)

  # get dimension
  num_snps = size(snpid, 1)

  # construct β
  β = zeros(Float64, num_snps)
  for i in 1:num_snps
    if (haskey(causal_snps, snpid[i]))
      β[i] = causal_snps[snpid[i]]
    end
  end

  return β

end

"""
"""
function simulate_liability(
    genotypes::SnpData,
    causal_snps::Dict{AbstractString, Float64},
    hsq::Float64,
    rep::Int64,
    missing_rate::Float64
  )

  # get dimensions
  num_snps = genotypes.snps
  num_people = genotypes.people

  # compute genetic component of the trait and its variance
  X = convert(Array{Float64, 2}, genotypes.snpmatrix,
        impute=true, center=true, scale=true)
  β = get_effect_size_vector(genotypes.snpid, causal_snps)
  Xβ = X * β
  σ2g = var(Xβ)

  # compute σ2e so that σ2g / (σ2g + σ2e) = hsq
  σ2e = σ2g * (1.0 - hsq) / hsq

  # modeling environmental component and missing rate
  norm_dist = Normal(0.0, sqrt(σ2e))
  bern_dist = Bernoulli(missing_rate)

  # simulate replicates
  Y = zeros(Float64, (num_people, rep))
  for i in 1:rep

    # draw environmental effect and generate phenotype
    ϵ = rand(norm_dist, num_people)
    Y[:,i] = Xβ + ϵ

    # mark traits as missing based on missing_rate
    for j in 1:num_people
      if (rand(bern_dist) == 1)
        Y[j,i] = NaN
      end
    end

  end

  return Y

end # end function sim_liability

"""
"""
function simulate_liability(
    genotypes::SnpData,
    causal_snps::NTuple{2, Dict{AbstractString, Float64}},
    hsq::NTuple{2, Float64},
    trait_cor::Float64,
    rep::Int64,
    missing_rate::NTuple{2, Float64}
  )

  # get dimensions
  num_snps = genotypes.snps
  num_people = genotypes.people
  (hsq1, hsq2) = hsq
  (missing_rate1, missing_rate2) = missing_rate
  (causal_snps1, causal_snps2) = causal_snps

  # compute genetic component of the trait and its variance
  X = convert(Array{Float64, 2}, genotypes.snpmatrix,
        impute=true, center=true, scale=true)
  β = get_effect_size_vector(genotypes.snpid, causal_snps1)
  γ = get_effect_size_vector(genotypes.snpid, causal_snps2)
  Xβ = X * β
  Xγ = X * γ
  σ2g1 = var(Xβ)
  σ2g2 = var(Xγ)
  ρg = cov(Xβ, Xγ)

  # compute σ2e so that σ2g / (σ2g + σ2e) = hsq
  σ2e1 = σ2g1 * (1.0 - hsq1) / hsq1
  σ2e2 = σ2g2 * (1.0 - hsq2) / hsq2

  # compute ρe so that correlation between the traits is cor
  σ2t1 = σ2g1 + σ2e1
  σ2t2 = σ2g2 + σ2e2
  ρt = trait_cor * sqrt(σ2t1*σ2t2)
  ρe = ρt - ρg

  # modeling environmental component and missing rate
  norm_dist = MvNormal([0.0; 0.0], [σ2e1 ρe; ρe σ2e2])
  bern_dist1 = Bernoulli(missing_rate1)
  bern_dist2 = Bernoulli(missing_rate2)

  # simulate replicates
  Y1 = zeros(Float64, (num_people, rep))
  Y2 = zeros(Float64, (num_people, rep))
  for i in 1:rep

    # draw environmental effect and generate phenotype
    ϵ = rand(norm_dist, num_people)
    Y1[:,i] = Xβ + ϵ[1,:]'
    Y2[:,i] = Xγ + ϵ[2,:]'

    # mark traits as missing based on missing_rate
    for j in 1:num_people
      if (rand(bern_dist1) == 1)
        Y1[j,i] = NaN
      end
      if (rand(bern_dist2) == 1)
        Y2[j,i] = NaN
      end
    end

  end

  return (Y1, Y2)

end # end function sim_liability

"""
"""
function simulate_case_control(
    genotypes::SnpData,
    causal_snps::Dict{AbstractString, Float64},
    hsq::Union{Float64, NTuple{2, Float64}},
    rep::Int64,
    prevalence::Float64,
    ncc::NTuple{2, Int64}
  )

  # get dimensions
  num_people = genotypes.people
  (num_cases, num_ctrls) = (ncc[1], ncc[2])

  # simulate the liability scores
  Y_liab = simulate_liability(genotypes, causal_snps, hsq, rep, 0.0)

  # simulate case control status
  Y::Array{Float64, 2} = fill(NaN, (num_people, rep))
  for i in 1:rep

    # get liability threshold
    k::Int64 = ceil(prevalence * num_people)
    sorted = sort(Y_liab[:,i], rev=true)
    threshold = sorted[k]

    # get case control indices
    case_indices = shuffle(find(Y_liab[:,i] .> threshold))[1:num_cases]
    ctrl_indices = shuffle(find(Y_liab[:,i] .<= threshold))[1:num_ctrls]

    # mark case contrl status
    Y[case_indices, i] = 1.0
    Y[ctrl_indices, i] = 0.0

  end

  return Y

end

end # end module
