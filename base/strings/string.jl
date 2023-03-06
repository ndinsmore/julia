# This file is a part of Julia. License is MIT: https://julialang.org/license

"""
    StringIndexError(str, i)

An error occurred when trying to access `str` at index `i` that is not valid.
"""
struct StringIndexError <: Exception
    string::AbstractString
    index::Integer
end
@noinline string_index_err(s::AbstractString, i::Integer) =
    throw(StringIndexError(s, Int(i)))
function Base.showerror(io::IO, exc::StringIndexError)
    s = exc.string
    print(io, "StringIndexError: ", "invalid index [$(exc.index)]")
    if firstindex(s) <= exc.index <= ncodeunits(s)
        iprev = thisind(s, exc.index)
        inext = nextind(s, iprev)
        escprev = escape_string(s[iprev:iprev])
        if inext <= ncodeunits(s)
            escnext = escape_string(s[inext:inext])
            print(io, ", valid nearby indices [$iprev]=>'$escprev', [$inext]=>'$escnext'")
        else
            print(io, ", valid nearby index [$iprev]=>'$escprev'")
        end
    end
end

const ByteArray = Union{CodeUnits{UInt8,String}, Vector{UInt8},Vector{Int8}, FastContiguousSubArray{UInt8,1,CodeUnits{UInt8,String}}, FastContiguousSubArray{UInt8,1,Vector{UInt8}}, FastContiguousSubArray{Int8,1,Vector{Int8}}}

@inline between(b::T, lo::T, hi::T) where {T<:Integer} = (lo ≤ b) & (b ≤ hi)

"""
    String <: AbstractString

The default string type in Julia, used by e.g. string literals.

`String`s are immutable sequences of `Char`s. A `String` is stored internally as
a contiguous byte array, and while they are interpreted as being UTF-8 encoded,
they can be composed of any byte sequence. Use [`isvalid`](@ref) to validate
that the underlying byte sequence is valid as UTF-8.
"""
String

## constructors and conversions ##

# String constructor docstring from boot.jl, workaround for #16730
# and the unavailability of @doc in boot.jl context.
"""
    String(v::AbstractVector{UInt8})

Create a new `String` object using the data buffer from byte vector `v`.
If `v` is a `Vector{UInt8}` it will be truncated to zero length and future
modification of `v` cannot affect the contents of the resulting string.
To avoid truncation of `Vector{UInt8}` data, use `String(copy(v))`; for other
`AbstractVector` types, `String(v)` already makes a copy.

When possible, the memory of `v` will be used without copying when the `String`
object is created. This is guaranteed to be the case for byte vectors returned
by [`take!`](@ref) on a writable [`IOBuffer`](@ref) and by calls to
[`read(io, nb)`](@ref). This allows zero-copy conversion of I/O data to strings.
In other cases, `Vector{UInt8}` data may be copied, but `v` is truncated anyway
to guarantee consistent behavior.
"""
String(v::AbstractVector{UInt8}) = String(copyto!(StringVector(length(v)), v))
String(v::Vector{UInt8}) = ccall(:jl_array_to_string, Ref{String}, (Any,), v)

"""
    unsafe_string(p::Ptr{UInt8}, [length::Integer])

Copy a string from the address of a C-style (NUL-terminated) string encoded as UTF-8.
(The pointer can be safely freed afterwards.) If `length` is specified
(the length of the data in bytes), the string does not have to be NUL-terminated.

This function is labeled "unsafe" because it will crash if `p` is not
a valid memory address to data of the requested length.
"""
function unsafe_string(p::Union{Ptr{UInt8},Ptr{Int8}}, len::Integer)
    p == C_NULL && throw(ArgumentError("cannot convert NULL to string"))
    ccall(:jl_pchar_to_string, Ref{String}, (Ptr{UInt8}, Int), p, len)
end
function unsafe_string(p::Union{Ptr{UInt8},Ptr{Int8}})
    p == C_NULL && throw(ArgumentError("cannot convert NULL to string"))
    ccall(:jl_cstr_to_string, Ref{String}, (Ptr{UInt8},), p)
end

# This is @assume_effects :effect_free :nothrow :terminates_globally @ccall jl_alloc_string(n::Csize_t)::Ref{String},
# but the macro is not available at this time in bootstrap, so we write it manually.
@eval _string_n(n::Integer) = $(Expr(:foreigncall, QuoteNode(:jl_alloc_string), Ref{String}, Expr(:call, Expr(:core, :svec), :Csize_t), 1, QuoteNode((:ccall,0xe)), :(convert(Csize_t, n))))

"""
    String(s::AbstractString)

Create a new `String` from an existing `AbstractString`.
"""
String(s::AbstractString) = print_to_string(s)
@assume_effects :total String(s::Symbol) = unsafe_string(unsafe_convert(Ptr{UInt8}, s))

unsafe_wrap(::Type{Vector{UInt8}}, s::String) = ccall(:jl_string_to_array, Ref{Vector{UInt8}}, (Any,), s)

Vector{UInt8}(s::CodeUnits{UInt8,String}) = copyto!(Vector{UInt8}(undef, length(s)), s)
Vector{UInt8}(s::String) = Vector{UInt8}(codeunits(s))
Array{UInt8}(s::String)  = Vector{UInt8}(codeunits(s))

String(s::CodeUnits{UInt8,String}) = s.s

## low-level functions ##

pointer(s::String) = unsafe_convert(Ptr{UInt8}, s)
pointer(s::String, i::Integer) = pointer(s) + Int(i)::Int - 1

ncodeunits(s::String) = Core.sizeof(s)
codeunit(s::String) = UInt8

@inline function codeunit(s::String, i::Integer)
    @boundscheck checkbounds(s, i)
    b = GC.@preserve s unsafe_load(pointer(s, i))
    return b
end

## comparison ##

_memcmp(a::Union{Ptr{UInt8},AbstractString}, b::Union{Ptr{UInt8},AbstractString}, len) =
    ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), a, b, len % Csize_t) % Int

function cmp(a::String, b::String)
    al, bl = sizeof(a), sizeof(b)
    c = _memcmp(a, b, min(al,bl))
    return c < 0 ? -1 : c > 0 ? +1 : cmp(al,bl)
end

function ==(a::String, b::String)
    pointer_from_objref(a) == pointer_from_objref(b) && return true
    al = sizeof(a)
    return al == sizeof(b) && 0 == _memcmp(a, b, al)
end

typemin(::Type{String}) = ""
typemin(::String) = typemin(String)

##
#=
 ┌─────────────────────────────────────────────────────┐
 │  INCLUSIVE    ┌──────────────2──────────────┐       │
 │    UTF-8      │                             │       │
 │               ├────────3────────┐           │       │
 │   IUTF-8      │                 │           │       │
 │    ┌─0─┐      │     ┌─┐        ┌▼┐         ┌▼┐      │
 │    │   │      ├─4──►│3├───1────►3├────1────►1├────┐ │
 │   ┌▼───┴┐     │     └─┘        └─┘         └─┘    │ │
 │   │  0  ├─────┘   Needs 3    Needs 2     Needs 1  │ │
 │   └───▲─┘        ContBytes  ContBytes   ContBytes │ │
 │       │                                           │ │
 │       │           ContByte=Transition 1           │ │
 │       └─────────────────────1─────────────────────┘ │
 │  ┌─┐                                                │
 │  │4│◄───All undefined transitions result in state 4 │
 │  └─┘      State machine must be reset after state 4 │
 └─────────────────────────────────────────────────────┘
=#
const _IUTF8State = UInt16
const _IUTF8_SHIFT_MASK = _IUTF8State(0b1111)
const _IUTF8_DFA_ACCEPT = _IUTF8State(0)
const _IUTF8_DFA_INVALID = _IUTF8State(1)

const _IUTF8_DFA_TABLE, _IUTF8_DFA_REVERSE_TABLE = begin

    shifts = [0, 9, 5, 13, 1]

    # Both of these state tables are only 4 states wide even thought there are 5 states
    # because the machine must be reset once it is in state 4
    forward_state_table  = [    [0,  4,  4,  4],
                                [4,  0,  1,  2],
                                [1,  4,  4,  4],
                                [2,  4,  4,  4],
                                [3,  4,  4,  4],
                                [4,  4,  4,  4] ]

    reverse_state_table  = [    [0,  4,  4,  4],
                                [1,  2,  3,  4],
                                [4,  0,  4,  4],
                                [4,  0,  0,  4],
                                [4,  0,  0,  0],
                                [4,  4,  4,  4] ]


    f(from,to) = _IUTF8State(shifts[to+1]) << shifts[from+1]
    r(state_row) = |([f(n-1,state_row[n]) for n = 1:length(state_row)]...)
    forward_class_rows = [r(forward_state_table[n]) for n = 1:length(forward_state_table)]
    reverse_class_rows = [r(reverse_state_table[n]) for n = 1:length(reverse_state_table)]

    byte_class = [  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,    #  0x00:0x0F      00000000:00001111
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,    #  0x10:0x1F      00010000:00011111
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,    #  0x20:0x2F      00100000:00101111
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,    #  0x30:0x3F      00110000:00111111
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,    #  0x40:0x4F      01000000:01001111
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,    #  0x50:0x5F      01010000:01011111
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,    #  0x60:0x6F      01100000:01101111
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,    #  0x70:0x7F      01110000:01111111
                    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,    #  0x80:0x8F      10000000:10001111
                    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,    #  0x90:0x9F      10010000:10011111
                    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,    #  0xA0:0xAF      10100000:10101111
                    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,    #  0xB0:0xBF      10110000:10111111
                    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,    #  0xC0:0xCF      11000000:11001111
                    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,    #  0xD0:0xDF      11010000:11011111
                    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,    #  0xE0:0xEF      11100000:11101111
                    4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5  ]  #  0xF0:0xFF      11110000:11111111
    forward_dfa_table = zeros(_IUTF8State,256)
    reverse_dfa_table = zeros(_IUTF8State,256)
    for n = 1:256
        forward_dfa_table[n] = forward_class_rows[1+byte_class[n]]
        reverse_dfa_table[n] = reverse_class_rows[1+byte_class[n]]
    end
    (forward_dfa_table, reverse_dfa_table)
end
##
@inline _iutf8_dfa_step(state::_IUTF8State, byte::UInt8) = @inbounds (_IUTF8_DFA_TABLE[byte+1] >> state) & _IUTF8_SHIFT_MASK
@inline _iutf8_dfa_isfinished(state::_IUTF8State) = state <= _IUTF8_DFA_INVALID

@inline _iutf8_dfa_reverse_step(state::_IUTF8State, byte::UInt8) = @inbounds (_IUTF8_DFA_REVERSE_TABLE[byte+1] >> state) & _IUTF8_SHIFT_MASK
@inline _iutf8_dfa_reverse_isfinished(state::_IUTF8State) = state <= _IUTF8_DFA_INVALID


## thisind, nextind ##

@propagate_inbounds thisind(s::String, i::Int) = _thisind_str(s, i)

# s should be String or SubString{String}
@inline function _thisind_str(s, i::Int)
    i == 0 && return 0
    n = ncodeunits(s)
    (i == n + 1)|( i == 1) && return i
    @boundscheck Base.between(i, 1, n) || throw(BoundsError(s, i))
    bytes = codeunits(s)
    state = _IUTF8_DFA_ACCEPT
    for j=0:3
        state  = @inbounds _iutf8_dfa_reverse_step(state,bytes[i - j])
        _iutf8_dfa_reverse_isfinished(state) | ((i - j) <= 1) && return ifelse(state > _IUTF8_DFA_ACCEPT, i, i - j)
    end
    return i
end

@propagate_inbounds nextind(s::String, i::Int) = _nextind_str(s, i)

# s should be String or SubString{String}
@inline function _nextind_str(s, i::Int)
    i == 0 && return 1
    n = ncodeunits(s)
    @boundscheck Base.between(i, 1, n) || throw(BoundsError(s, i))
    @inbounds l = codeunit(s, i)
    (l < 0x80) | (0xf8 ≤ l) && return i+1
    if l < 0xc0
        i′ = @inbounds _thisind_str(s, i)
        return i′ < i ? @inbounds(_nextind_str(s, i′)) : i+1
    end
    state = _IUTF8_DFA_ACCEPT
    for j=0:3
        state  = _iutf8_dfa_step(state,codeunit(s, i + j))
        (_iutf8_dfa_isfinished(state) | ((i + j) >= n)) && return ifelse(state == _IUTF8_DFA_INVALID,i+j,i + j + 1)
    end
    return i + 4
end

## checking UTF-8 & ACSII validity ##

byte_string_classify(s::Union{String,Vector{UInt8},FastContiguousSubArray{UInt8,1,Vector{UInt8}}}) =
    ccall(:u8_isvalid, Int32, (Ptr{UInt8}, Int), s, sizeof(s))
    # 0: neither valid ASCII nor UTF-8
    # 1: valid ASCII
    # 2: valid UTF-8

isvalid(::Type{String}, s::Union{Vector{UInt8},FastContiguousSubArray{UInt8,1,Vector{UInt8}},String}) = byte_string_classify(s) ≠ 0
isvalid(s::String) = isvalid(String, s)

is_valid_continuation(c) = c & 0xc0 == 0x80

## required core functionality ##

@inline function iterate(s::String, i::Int=firstindex(s))
    (i % UInt) - 1 < ncodeunits(s) || return nothing
    b = @inbounds codeunit(s, i)
    u = UInt32(b) << 24
    between(b, 0x80, 0xf7) || return reinterpret(Char, u), i+1
    return iterate_continued(s, i, u)
end

function iterate_continued(s::String, i::Int, u::UInt32)
    u < 0xc0000000 && (i += 1; @goto ret)
    n = ncodeunits(s)
    # first continuation byte
    (i += 1) > n && @goto ret
    @inbounds b = codeunit(s, i)
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b) << 16
    # second continuation byte
    ((i += 1) > n) | (u < 0xe0000000) && @goto ret
    @inbounds b = codeunit(s, i)
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b) << 8
    # third continuation byte
    ((i += 1) > n) | (u < 0xf0000000) && @goto ret
    @inbounds b = codeunit(s, i)
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b); i += 1
@label ret
    return reinterpret(Char, u), i
end

@propagate_inbounds function getindex(s::String, i::Int)
    b = codeunit(s, i)
    u = UInt32(b) << 24
    between(b, 0x80, 0xf7) || return reinterpret(Char, u)
    return getindex_continued(s, i, u)
end

function getindex_continued(s::String, i::Int, u::UInt32)
    if u < 0xc0000000
        # called from `getindex` which checks bounds
        @inbounds isvalid(s, i) && @goto ret
        string_index_err(s, i)
    end
    n = ncodeunits(s)

    (i += 1) > n && @goto ret
    @inbounds b = codeunit(s, i) # cont byte 1
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b) << 16

    ((i += 1) > n) | (u < 0xe0000000) && @goto ret
    @inbounds b = codeunit(s, i) # cont byte 2
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b) << 8

    ((i += 1) > n) | (u < 0xf0000000) && @goto ret
    @inbounds b = codeunit(s, i) # cont byte 3
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b)
@label ret
    return reinterpret(Char, u)
end

getindex(s::String, r::AbstractUnitRange{<:Integer}) = s[Int(first(r)):Int(last(r))]

@inline function getindex(s::String, r::UnitRange{Int})
    isempty(r) && return ""
    i, j = first(r), last(r)
    @boundscheck begin
        checkbounds(s, r)
        @inbounds isvalid(s, i) || string_index_err(s, i)
        @inbounds isvalid(s, j) || string_index_err(s, j)
    end
    j = nextind(s, j) - 1
    n = j - i + 1
    ss = _string_n(n)
    GC.@preserve s ss unsafe_copyto!(pointer(ss), pointer(s, i), n)
    return ss
end

length(s::String) = length_continued(s, 1, ncodeunits(s), ncodeunits(s))

@inline function length(s::String, i::Int, j::Int)
    @boundscheck begin
        0 < i ≤ ncodeunits(s)+1 || throw(BoundsError(s, i))
        0 ≤ j < ncodeunits(s)+1 || throw(BoundsError(s, j))
    end
    j < i && return 0
    @inbounds i, k = thisind(s, i), i
    c = j - i + (i == k)
    length_continued(s, i, j, c)
end

@inline function length_continued(s::String, i::Int, n::Int, c::Int)
    i < n || return c
    @inbounds b = codeunit(s, i)
    @inbounds while true
        while true
            (i += 1) ≤ n || return c
            0xc0 ≤ b ≤ 0xf7 && break
            b = codeunit(s, i)
        end
        l = b
        b = codeunit(s, i) # cont byte 1
        c -= (x = b & 0xc0 == 0x80)
        x & (l ≥ 0xe0) || continue

        (i += 1) ≤ n || return c
        b = codeunit(s, i) # cont byte 2
        c -= (x = b & 0xc0 == 0x80)
        x & (l ≥ 0xf0) || continue

        (i += 1) ≤ n || return c
        b = codeunit(s, i) # cont byte 3
        c -= (b & 0xc0 == 0x80)
    end
end

## overload methods for efficiency ##

isvalid(s::String, i::Int) = checkbounds(Bool, s, i) && thisind(s, i) == i

isascii(s::String) = isascii(codeunits(s))

"""
    repeat(c::AbstractChar, r::Integer) -> String

Repeat a character `r` times. This can equivalently be accomplished by calling
[`c^r`](@ref :^(::Union{AbstractString, AbstractChar}, ::Integer)).

# Examples
```jldoctest
julia> repeat('A', 3)
"AAA"
```
"""
repeat(c::AbstractChar, r::Integer) = repeat(Char(c), r) # fallback
function repeat(c::Char, r::Integer)
    r == 0 && return ""
    r < 0 && throw(ArgumentError("can't repeat a character $r times"))
    u = bswap(reinterpret(UInt32, c))
    n = 4 - (leading_zeros(u | 0xff) >> 3)
    s = _string_n(n*r)
    p = pointer(s)
    GC.@preserve s if n == 1
        ccall(:memset, Ptr{Cvoid}, (Ptr{UInt8}, Cint, Csize_t), p, u % UInt8, r)
    elseif n == 2
        p16 = reinterpret(Ptr{UInt16}, p)
        for i = 1:r
            unsafe_store!(p16, u % UInt16, i)
        end
    elseif n == 3
        b1 = (u >> 0) % UInt8
        b2 = (u >> 8) % UInt8
        b3 = (u >> 16) % UInt8
        for i = 0:r-1
            unsafe_store!(p, b1, 3i + 1)
            unsafe_store!(p, b2, 3i + 2)
            unsafe_store!(p, b3, 3i + 3)
        end
    elseif n == 4
        p32 = reinterpret(Ptr{UInt32}, p)
        for i = 1:r
            unsafe_store!(p32, u, i)
        end
    end
    return s
end
