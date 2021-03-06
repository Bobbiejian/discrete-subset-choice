include("common.jl")
using LinearAlgebra
using Optim, LineSearches
using Printf
using StatsBase

# Represent a variable choice dataset as a vector of slate sizes, a vector of
# all slates, a vector of choice set sizes, and a vector of all choices.
mutable struct VariableChoiceDataset
    slate_sizes::Vector{Int64}
    slates::Vector{Int64}
    choice_sizes::Vector{Int64}
    choices::Vector{Int64}
end

# Utility-based variable choice model.
#
# -z is a vector of length max_size with the probability of choosing
#  a size-k subset being z[k]
# -utilities are the item utilities
# -H is a vector of length max_size where each element
#  is a dictionary that maps a choice set to a utility.
mutable struct VariableChoiceModel
    z::Vector{Float64}
    utilities::Vector{Float64}
    H::Dict{NTuple,Float64}
end

# Read text data
function read_data(dataset::AbstractString)
    f = open(dataset)
    slate_sizes = Int64[]
    slates = Int64[]
    choice_sizes = Int64[]    
    choices = Int64[]
    for line in eachline(f)
        slate_choice = split(line, ";")
        slate = [parse(Int64, v) for v in split(slate_choice[1])]
        sort!(slate)
        choice = [parse(Int64, v) for v in split(slate_choice[2])]
        sort!(choice)
        push!(slate_sizes, length(slate))
        append!(slates, slate)
        push!(choice_sizes, length(choice))
        append!(choices, choice)
    end
    return VariableChoiceDataset(slate_sizes, slates, choice_sizes, choices)
end

in_H(model::VariableChoiceModel, choice::Vector{Int64}) =
    haskey(model.H, vec2ntuple(choice))
H_val(model::VariableChoiceModel, choice::Vector{Int64}) =
    get(model.H, vec2ntuple(choice), 0.0)

function set_H_value!(model::VariableChoiceModel, choice::Vector{Int64}, val::Float64)
    model.H[vec2ntuple(choice)] = val
end

function set_H_value!(model::VariableChoiceModel, choice::NTuple, val::Float64)
    model.H[choice] = val
end

function add_to_H!(model::VariableChoiceModel, choice_to_add::Vector{Int64})
    if in_H(model, choice_to_add); error("Choice already in hot set."); end
    set_H_value!(model, choice_to_add, 0.0)
end

# sum of exponential of subset-sum utilities for size-1 subsets 
function sumexp_util1(model::VariableChoiceModel, slate::Vector{Int64})
    ns = length(slate)
    total = 0.0
    utils = [model.utilities[s] for s in slate]    
    for i = 1:ns
        total += exp(utils[i])
    end
    return total
end

# sum of exponential of subset-sum utilities for size-2 subsets 
function sumexp_util2(model::VariableChoiceModel, slate::Vector{Int64})
    ns = length(slate)
    total = 0.0
    subset = [0, 0]
    utils = [model.utilities[s] for s in slate]    
    for i = 1:ns
        subset[1] = slate[i]
        si = utils[i]
        for j = i:ns
            subset[2] = slate[j]
            sj = si + utils[j] + H_val(model, subset)
            total += exp(sj)
        end
    end
    return total
end

# sum of exponential of subset-sum utilities for size-3 subsets 
function sumexp_util3(model::VariableChoiceModel, slate::Vector{Int64})
    ns = length(slate)
    total = 0.0
    subset = [0, 0, 0]
    utils = [model.utilities[s] for s in slate]    
    for i = 1:ns
        subset[1] = slate[i]
        si = utils[i]
        for j = i:ns
            subset[2] = slate[j]
            sj = si + utils[j]
            for k = j:ns
                subset[3] = slate[k]
                sk = sj + utils[k] + H_val(model, subset)
                total += exp(sk)
            end
        end
    end
    return total
end

# sum of exponential of subset-sum utilities for size-4 subsets 
function sumexp_util4(model::VariableChoiceModel, slate::Vector{Int64})
    ns = length(slate)
    total = 0.0
    subset = [0, 0, 0, 0]
    utils = [model.utilities[s] for s in slate]    
    for i = 1:ns
        subset[1] = slate[i]
        si = utils[i]
        for j = i:ns
            subset[2] = slate[j]
            sj = si + utils[j]
            for k = j:ns
                subset[3] = slate[k]
                sk = sj + utils[k]
                for l = k:ns
                    subset[4] = slate[l]
                    sl = sk + utils[l] + H_val(model, subset)
                    total += exp(sl)
                end
            end
        end
    end
    return total
end

# sum of exponential of subset-sum utilities for size-5 subsets 
function sumexp_util5(model::VariableChoiceModel, slate::Vector{Int64})
    ns = length(slate)
    total = 0.0
    subset = [0, 0, 0, 0, 0]
    utils = [model.utilities[s] for s in slate]
    for i = 1:ns
        subset[1] = slate[i]
        si = utils[i]
        for j = i:ns
            subset[2] = slate[j]
            sj = si + utils[j]
            for k = j:ns
                subset[3] = slate[k]
                sk = sj + utils[k]
                for l = k:ns
                    subset[4] = slate[l]
                    sl = sk + utils[l]
                    for m = l:ns
                        subset[5] = slate[m]
                        sm = sl + utils[m] + H_val(model, subset)
                        total += exp(sm)
                    end
                end
            end
        end
    end
    return total
end

function gradient_update1!(model::VariableChoiceModel, slate::Vector{Int64},
                           grad::Vector{Float64})
    sum = sumexp_util1(model, slate)
    if isnan(sum); error("Sum is NaN"); end
    ns = length(slate)
    utils = [model.utilities[s] for s in slate]        
    for i = 1:ns
        grad[slate[i]] += exp(utils[i]) / sum
    end
end

function gradient_update2!(model::VariableChoiceModel, slate::Vector{Int64},
                           grad::Vector{Float64}, H_inds::Dict{NTuple, Int64})
    sum = sumexp_util2(model, slate)
    if isnan(sum); error("Sum is NaN"); end    
    ns = length(slate)
    subset = [0, 0]
    utils = [model.utilities[s] for s in slate]    
    for i = 1:ns
        subset[1] = slate[i]
        si = model.utilities[i]
        for j = i:ns
            subset[2] = slate[j]
            sj = si + utils[j] + H_val(model, subset)
            for elmt in subset; grad[elmt] += exp(sj) / sum; end
            if in_H(model, subset)
                grad[H_inds[vec2ntuple(subset)]] += exp(sj) / sum
            end
        end
    end
end

function gradient_update3!(model::VariableChoiceModel, slate::Vector{Int64},
                           grad::Vector{Float64}, H_inds::Dict{NTuple, Int64})
    sum = sumexp_util3(model, slate)
    if isnan(sum); error("Sum is NaN"); end    
    ns = length(slate)
    subset = [0, 0, 0]
    utils = [model.utilities[s] for s in slate]    
    for i = 1:ns
        subset[1] = slate[i]
        si = utils[i]
        for j = i:ns
            subset[2] = slate[j]
            sj = si + utils[j]
            for k = j:ns
                subset[3] = slate[k]
                sk = sj + utils[k] + H_val(model, subset)
                for elmt in subset; grad[elmt] += exp(sk) / sum; end
                if in_H(model, subset)
                    grad[H_inds[vec2ntuple(subset)]] += exp(sk) / sum
                end
            end
        end
    end
end

function gradient_update4!(model::VariableChoiceModel, slate::Vector{Int64},
                           grad::Vector{Float64}, H_inds::Dict{NTuple, Int64})
    sum = sumexp_util4(model, slate)
    if isnan(sum); error("Sum is NaN"); end    
    ns = length(slate)
    subset = [0, 0, 0, 0]
    utils = [model.utilities[s] for s in slate]    
    for i = 1:ns
        subset[1] = slate[i]
        si = utils[i]
        for j = i:ns
            subset[2] = slate[j]
            sj = si + utils[j]
            for k = j:ns
                subset[3] = slate[k]
                sk = sj + utils[k]
                for l = k:ns
                    subset[4] = slate[l]
                    sl = sk + utils[l] + H_val(model, subset)
                    for elmt in subset; grad[elmt] += exp(sl) / sum; end
                    if in_H(model, subset)
                        grad[H_inds[vec2ntuple(subset)]] += exp(sl) / sum
                    end
                end
            end
        end
    end
end

function gradient_update5!(model::VariableChoiceModel, slate::Vector{Int64},
                           grad::Vector{Float64}, H_inds::Dict{NTuple, Int64})
    sum = sumexp_util5(model, slate)
    if isnan(sum); error("Sum is NaN"); end
    ns = length(slate)
    subset = [0, 0, 0, 0, 0]
    utils = [model.utilities[s] for s in slate]    
    for i = 1:ns
        subset[1] = slate[i]
        si = utils[i]
        for j = i:ns
            subset[2] = slate[j]
            sj = si + utils[j]
            for k = j:ns
                subset[3] = slate[k]
                sk = sj + utils[k]
                for l = k:ns
                    subset[4] = slate[l]
                    sl = sk + utils[l]
                    for m = l:ns
                        subset[5] = slate[m]
                        sm = sl + utils[m] + H_val(model, subset)
                        for elmt in subset; grad[elmt] += exp(sm) / sum; end
                        if in_H(model, subset)
                            grad[H_inds[vec2ntuple(subset)]] += exp(sm) / sum
                        end
                    end
                end
            end
        end
    end
end


# Given a slate, takes the sum of the exponential of the set utilities for all
# size-k subsets of the slate.  There is one function for each of k = 1, 2, 3, 4, 5.
function sumexp_util(model::VariableChoiceModel, slate::Vector{Int64}, size::Int64)
    if     size == 1; return sumexp_util1(model, slate)
    elseif size == 2; return sumexp_util2(model, slate)
    elseif size == 3; return sumexp_util3(model, slate)
    elseif size == 4; return sumexp_util4(model, slate)
    elseif size == 5; return sumexp_util5(model, slate)
    else error(@sprintf("Cannot handle size %d", size))
    end
end

function update_gradient_from_slate!(model::VariableChoiceModel, grad::Vector{Float64}, slate::Vector{Int64},
                                     choice_size::Int64, H_inds::Dict{NTuple, Int64})
    if     choice_size == 1; gradient_update1!(model, slate, grad)
    elseif choice_size == 2; gradient_update2!(model, slate, grad, H_inds)
    elseif choice_size == 3; gradient_update3!(model, slate, grad, H_inds)
    elseif choice_size == 4; gradient_update4!(model, slate, grad, H_inds)
    elseif choice_size == 5; gradient_update5!(model, slate, grad, H_inds)
    else error(@sprintf("Cannot handle size %d", choice_size))
    end
end
        
function log_likelihood(model::VariableChoiceModel, data::VariableChoiceDataset)
    ns = length(data.slate_sizes)
    ll = zeros(Float64, ns)
    slate_inds  = index_points(data.slate_sizes)
    choice_inds = index_points(data.choice_sizes)
    for i = 1:ns
        slate  = data.slates[slate_inds[i]:(slate_inds[i + 1] - 1)]        
        choice = data.choices[choice_inds[i]:(choice_inds[i + 1] - 1)]
        size = length(choice)
        max_ind = min(length(model.z), length(slate) - 1)
        ll[i] += log(model.z[size] / sum(model.z[1:max_ind]))
        for item in choice; ll[i] += model.utilities[item]; end
        ll[i] += H_val(model, choice)
        ll[i] -= log(sumexp_util(model, slate, size))
    end
    return sum(ll)
end

function learn_utilities!(model::VariableChoiceModel, data::VariableChoiceDataset)
    n_items = length(model.utilities)
    H_tups = Vector{NTuple}()
    H_inds = Dict{NTuple, Int64}()
    H_vals = Float64[]
    for (tup, val) in model.H
        push!(H_tups, tup)
        H_inds[tup] = n_items + length(H_tups)
        push!(H_vals, val)
    end
    
    function update_model!(x::Vector{Float64})
        # Vector x contains item utilities and H utilities
        x[findall(isnan.(x))] .= 0.0
        model.utilities = copy(x[1:n_items])
        for (tup, val) in zip(H_tups, x[(n_items + 1):end])
            set_H_value!(model, tup, val)
        end
    end

    function neg_log_likelihood!(x::Vector{Float64})
        update_model!(x)
        return -log_likelihood(model, data)
    end

    slate_inds = index_points(data.slate_sizes)
    choice_inds = index_points(data.choice_sizes)
    function gradient!(grad::Vector{Float64}, x::Vector{Float64})
        for i = 1:length(x); grad[i] = 0.0; end
        update_model!(x)
        for i = 1:length(data.slate_sizes)
            slate = data.slates[slate_inds[i]:(slate_inds[i + 1] - 1)]        
            choice = data.choices[choice_inds[i]:(choice_inds[i + 1] - 1)]
            size = length(choice)
            for item in choice; grad[item] -= 1; end
            if in_H(model, choice)
                grad[H_inds[vec2ntuple(choice)]] -= 1
            end
            update_gradient_from_slate!(model, grad, slate, size, H_inds) 
        end
        # scale the gradient because the exponentials can get too large
        gnorm = norm(grad, 2.0)
        if gnorm > 10
            for i = 1:length(x); grad[i] /= gnorm; end
        end
        @show maximum(x)
    end

    options = Optim.Options(f_tol=1e-3, show_trace=true, show_every=1,
                            extended_trace=true, f_calls_limit=25)
    x0 = [copy(model.utilities); H_vals]
    res = optimize(neg_log_likelihood!, gradient!, x0,
                   LBFGS(; linesearch=BackTracking()), options)
    update_model!(res.minimizer)
end

function learn_size_probs!(model::VariableChoiceModel, data::VariableChoiceDataset)
    function neg_log_likelihood(x::Vector{Float64})
        nll = 0.0
        for (slate_size, choice_size) in zip(data.slate_sizes, data.choice_sizes)
            nll -= x[choice_size]
            total = 0.0
            max_choice_size = min(slate_size - 1, length(x))            
            for i in 1:max_choice_size; total += exp(x[i]); end
            nll += log(total)
        end
        return nll
    end

    function gradient!(grad::Vector{Float64}, x::Vector{Float64})
        # Note: assume utility of first element is 0
        for i = 1:length(x); grad[i] = 0.0; end
        for (slate_size, choice_size) in zip(data.slate_sizes, data.choice_sizes)
            if choice_size > 1; grad[choice_size] -= 1; end
            total = 1.0
            max_choice_size = min(slate_size - 1, length(x))
            for i in 2:max_choice_size; total += exp(x[i]); end
            grad[2:max_choice_size] += exp.(x[2:max_choice_size]) ./ total
        end
    end

    options = Optim.Options(f_tol=1e-6, show_trace=true, show_every=1, extended_trace=true)    
    res = optimize(neg_log_likelihood, gradient!,
                   zeros(Float64, maximum(data.choice_sizes)), LBFGS(), options)
    model.z = exp.(res.minimizer) / sum(exp.(res.minimizer))
end

function initialize_model(data::VariableChoiceDataset)
    max_choice_size = maximum(data.choice_sizes)
    z = ones(Float64, max_choice_size) / max_choice_size
    utilities = zeros(Float64, maximum(data.slates))
    H = Dict{NTuple, Float64}()
    return VariableChoiceModel(z, utilities, H)
end

function learn_model!(model::VariableChoiceModel, data::VariableChoiceDataset)
    learn_size_probs!(model, data)
    learn_utilities!(model, data)
end
