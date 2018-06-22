export stack, unstack, create_dummies

"""
`stack(t, by = pkeynames(t); select = excludecols(t, by), variable = :variable, value = :value)`

Reshape a table from the wide to the long format. Columns in `by` are kept as indexing columns.
Columns in `select` are stacked. In addition to the id columns, two additional columns labeled `variable` and `value`
are added, containg the column identifier and the stacked columns.

## Examples

```jldoctest stack
julia> t = table(1:4, [1, 4, 9, 16], [1, 8, 27, 64], names = [:x, :xsquare, :xcube], pkey = :x);

julia> stack(t)
Table with 8 rows, 3 columns:
x  variable  value
──────────────────
1  :xsquare  1
1  :xcube    1
2  :xsquare  4
2  :xcube    8
3  :xsquare  9
3  :xcube    27
4  :xsquare  16
4  :xcube    64
```
"""
function stack(t::D, by = pkeynames(t); select = isa(t, NDSparse) ? valuenames(t) : excludecols(t, by),
    variable = :variable, value = :value) where {D<:Dataset}

    (by != pkeynames(t)) && return stack(reindex(t, by, select); variable = :variable, value = :value)

    valuecols = columns(t, select)
    valuecol = [valuecol[i] for i in 1:length(t) for valuecol in valuecols]

    labels = fieldnames(valuecols)
    labelcol = [label for i in 1:length(t) for label in labels]

    bycols = map(arg -> repeat(arg, inner = length(valuecols)), columns(t, by))
    convert(collectiontype(D), Columns(bycols), Columns(labelcol, valuecol, names = [variable, value]))
end

function unstack(::Type{D}, ::Type{T}, key, val, cols::AbstractVector{S}) where {D <:Dataset, T, S}
    dest_val = Columns((DataValues.DataValueArray{T}(length(val)) for i in cols)...; names = cols)
    for (i, el) in enumerate(val)
        for j in el
            k, v = j
            isnull(columns(dest_val, S(k))[i]) || error("Repeated values with same label are not allowed")
            columns(dest_val, S(k))[i] = v
        end
    end
    convert(collectiontype(D), key, dest_val)
end

"""
`unstack(t, by = pkeynames(t); variable = :variable, value = :value)`

Reshape a table from the long to the wide format. Columns in `by` are kept as indexing columns.
Keyword arguments `variable` and `value` denote which column contains the column identifier and
which the corresponding values.

## Examples

```jldoctest unstack
julia> t = table(1:4, [1, 4, 9, 16], [1, 8, 27, 64], names = [:x, :xsquare, :xcube], pkey = :x);

julia> long = stack(t)
Table with 8 rows, 3 columns:
x  variable  value
──────────────────
1  :xsquare  1
1  :xcube    1
2  :xsquare  4
2  :xcube    8
3  :xsquare  9
3  :xcube    27
4  :xsquare  16
4  :xcube    64

julia> unstack(long)
Table with 4 rows, 3 columns:
x  xsquare  xcube
─────────────────
1  1        1
2  4        8
3  9        27
4  16       64
```
"""
function unstack(t::D, by = pkeynames(t); variable = :variable, value = :value) where {D<:Dataset}
    tgrp = groupby((value => identity,), t, by, select = (variable, value))
    S = eltype(colnames(t))
    cols = S.(union(columns(t, variable)))
    T = eltype(columns(t, value))
    unstack(D, T isa Type{<:DataValue} ? eltype(T) : T, pkeys(tgrp), columns(tgrp, value), cols)
end

"""
`create_dummies(t, cols; categories = Dict())`

Create a column corresponding to every categorical value present in the columns specified. `cols` is supposed be 
an array of column names or a single column name (`Symbol`) on which the dummy variables are to be created. 
The columns would have a 1 for the row with the value corresponding with the `val` as specified in the column name and 0 otherwise.
`categories` is a dictionary from column name to a vector of specific unique values.

## Examples

```jldoctest create_dummies
julia> t = table([1, 4, 9, 16], ["val1", "val1", "val2", "val2"], names = [:x, :y], pkey = :x);

julia> create_dummies(t, :y)
Table with 4 rows, 3 columns:
x   y_val1   y_val2
──────────────────
1   1        0
4   1        0
9   0        1
16  0        1

julia> t = table([1, 4, 9, 16], ["val1", "val1", "val2", "val2"], names = [:x, :y], pkey = :x);

julia> create_dummies(t, :y, categories = Dict(:y => ["val1"]))
Table with 4 rows, 3 columns:
x   y_val1 
───────────
1      1
4      1
9      0
16     0
```

"""

function create_dummies(t, cols; categories=Dict())
    for i in cols
        if haskey(categories, i)
            uniq = categories[i]
        else
            uniq = collect(keys(reduce(CountMap(), t, select = i).value))
        end
        for j in uniq
            t = setcol(t, Symbol("$(i)_$(j)"), i => x -> x == j ? Int8(1) : Int8(0))
        end
        t = popcol(t, i)
    end
    t
end

create_dummies(t, col::Symbol; categories = Dict()) = create_dummies(t, [col], categories = categories)

