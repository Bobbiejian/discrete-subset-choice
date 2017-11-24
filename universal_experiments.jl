include("universal.jl")

function top_choice_tups(data::UniversalChoiceDataset, num::Int64)
    counts = [(count, tup) for (tup, count) in get_subset_counts(data) if length(tup) > 1]
    sort!(counts, rev=true)
    return [collect(tup) for (count, tup) in counts[1:num]]
end

function negative_corrections_experiment(data::UniversalChoiceDataset, num_updates::Int64,
                                         basename::AbstractString)
    choices_to_add = top_choice_tups(data, num_updates)
    model = initialize_model(data)
    num_negative_corrections = Int64[]
    for (i, choice) in enumerate(choices_to_add)
        println(@sprintf("iteration %d of %d", i, num_updates))
        add_to_hotset!(model, choice)

        # Get negative corrections
        count = 0
        for (subset, val) in model.H
            separable_prob = prod([model.probs[item] for item in subset])
            gamma = model.gammas[length(subset)]
            correction = val - gamma * separable_prob
            if correction < 0; count += 1; end
        end
        push!(num_negative_corrections, count)
    end

    output = open("output/$basename-freq-neg-corrections.txt", "w")
    for (i, num) in enumerate(num_negative_corrections)
        write(output, @sprintf("%d %d\n", i, num))
    end
end

function biggest_corrections_experiment(data::UniversalChoiceDataset, num_updates::Int64,
                                        basename::AbstractString)
    choices_to_add = top_choice_tups(data, num_updates)
    model = initialize_model(data)
    num_negative_corrections = Int64[]
    for choice in choices_to_add; add_to_hotset!(model, choice); end

    data = []
    for (subset, val) in model.H
        separable_prob = prod([model.probs[item] for item in subset])
        gamma = model.gammas[length(subset)]
        correction = val - gamma * separable_prob
        push!(data, (correction, subset))
    end

    sort!(data)
    output = open("output/$basename-biggest-corrections.txt", "w")
    for i = 1:5
        write(output, @sprintf("%d:\t%s\t%f\n", i, join(data[i][2], " "), data[i][1]))
    end
    for i = 1:5
        ind = length(data) - i + 1
        write(output, @sprintf("%d:\t%s\t%f\n", i, join(data[ind][2], " "), data[ind][1]))
    end
end


function universal_improvements(data::UniversalChoiceDataset, num_updates::Int64,
                                basename::AbstractString, update_type::AbstractString,
                                timing::Bool=false)

    # Vector for randomly splitting into training / test data
    n = length(data.sizes)
    log_likelihoods = zeros(Float64, num_updates + 1)

    # Split into training / test data
    training_end = convert(Int64, floor(0.8 * n))
    training_sizes   = Int64[]
    training_choices = Int64[]
    test_sizes       = Int64[]
    test_choices     = Int64[]
    for (ind, (size, choice)) in enumerate(iter_choices(data))
        if ind <= training_end
            push!(training_sizes, size)
            append!(training_choices, choice)
        else
            push!(test_sizes, size)
            append!(test_choices, choice)
        end
    end
    training_data = UniversalChoiceDataset(training_sizes, training_choices)
    test_data = UniversalChoiceDataset(test_sizes, test_choices)
    model = initialize_model(training_data)
    log_likelihoods[1] = log_likelihood(model, test_data)
    
    item_counts = zeros(Int64, maximum(data.choices))
    for (size, choice) in iter_choices(training_data)
        for item in choice; item_counts[item] += 1; end
    end

    choices_to_add = top_choice_tups(training_data, num_updates)
    if     update_type == "f"
        # Keep frequency-based updates
    elseif update_type == "nl"
        # normalized lift-based updates
        lifts = Vector{Tuple{Float64,NTuple}}()
        for (choice_tup, subset_count) in get_subset_counts(training_data)
            if length(choice_tup) > 1
                subset_item_counts = [item_counts[item] for item in choice_tup]
                push!(lifts, (subset_count^2 / prod(subset_item_counts), choice_tup))
            end
        end
        sort!(lifts, rev=true)
        choices_to_add = [collect(choice_tup) for (_, choice_tup) in lifts[1:num_updates]]
    elseif update_type == "l"
        # Lift-based updates
        lifts = Vector{Tuple{Float64,NTuple}}()
        for (choice_tup, subset_count) in get_subset_counts(training_data)
            if length(choice_tup) > 1
                subset_item_counts = [item_counts[item] for item in choice_tup]
                push!(lifts, (subset_count / prod(subset_item_counts), choice_tup))
            end
        end
        sort!(lifts, rev=true)
        choices_to_add = [collect(choice_tup) for (_, choice_tup) in lifts[1:num_updates]]
    else
        error("Unknown update type")
    end

    for (i, choice) in enumerate(choices_to_add)
        add_to_hotset!(model, choice)
        if !timing;
            println(@sprintf("iteration %d of %d", i, num_updates))
            log_likelihoods[i + 1] = log_likelihood(model, test_data)
        end
    end

    # If we are doing a timing experiment, we are done.
    if timing
        log_likelihoods[end] = log_likelihood(model, test_data)
        return
    end

    if     update_type == "f";   output = open("output/$basename-single-freq.txt", "w")
    elseif update_type == "l";   output = open("output/$basename-single-lift.txt", "w")
    elseif update_type == "nl";  output = open("output/$basename-single-nlift.txt", "w")
    else   error("Unknown update type")    end
    for i = 0:num_updates
        write(output, @sprintf("%d %s\n", i, join(log_likelihoods[i + 1, :], " ")))
    end
end

function timing_experiments()
    function run_experiment(dataset_file::AbstractString)
        data = read_data(dataset_file)
        basename = split(split(dataset_file, "/")[end], ".")[1]
        num_items = length(unique(data.choices))        
        num_updates = min(num_items, 10000)

        # warmup
        universal_improvements(data, num_updates, basename, "f", true)
        # run
        tic()
        @time universal_improvements(data, num_updates, basename, "f", true)
        tf = toc()
        f = open("$basename-times.txt", "w")
        write(f, @sprintf("freq: %f\n", tf))
        close(f)
    end

    timing_experiment("data/bakery-5-25-clean.txt")
    timing_experiment("data/walmart-depts-5-25-clean.txt")
    timing_experiment("data/walmart-items-5-25-clean.txt")
    timing_experiment("data/lastfm-genres-5-25-clean.txt")
    timing_experiment("data/kosarak-5-25-clean.txt")
    timing_experiment("data/instacart-5-25-clean.txt")
end

function universal_improvement_experiments()
    function run_universal_improvement_experiment(dataset_file::AbstractString)
        data = read_data(dataset_file)
        basename = split(split(dataset_file, "/")[end], ".")[1]
        num_items = length(unique(data.choices))
        num_updates = min(num_items, 10000)
        universal_improvements(data, num_updates, basename, "f")        
        universal_improvements(data, num_updates, basename, "nl")
        universal_improvements(data, num_updates, basename, "l")
    end

    run_universal_improvement_experiment("data/bakery-5-25-clean.txt")
    run_universal_improvement_experiment("data/walmart-depts-5-25-clean.txt")
    run_universal_improvement_experiment("data/walmart-items-5-25-clean.txt")
    run_universal_improvement_experiment("data/lastfm-genres-5-25-clean.txt")
    run_universal_improvement_experiment("data/kosarak-5-25-clean.txt")
    run_universal_improvement_experiment("data/instacart-5-25-clean.txt")
end
