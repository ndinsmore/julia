# This file is a part of Julia. License is MIT: https://julialang.org/license

## semantic version numbers (https://semver.org/)

const VerTuple = Tuple{Vararg{Union{UInt64,String}}}

const VInt = UInt32
"""
    VersionNumber

Version number type which follows the specifications of
[semantic versioning (semver)](https://semver.org/spec/v2.0.0-rc.2.html), composed of major, minor
and patch numeric values, followed by pre-release and build
alphanumeric annotations.

`VersionNumber` objects can be compared with all of the standard comparison
operators (`==`, `<`, `<=`, etc.), with the result following semver v2.0.0-rc.2 rules.

`VersionNumber` has the following public fields:
- `v.major::Integer`
- `v.minor::Integer`
- `v.patch::Integer`
- `v.prerelease::Tuple{Vararg{Union{Integer, AbstractString}}}`
- `v.build::Tuple{Vararg{Union{Integer, AbstractString}}}`

See also [`@v_str`](@ref) to efficiently construct `VersionNumber` objects
from semver-format literal strings, [`VERSION`](@ref) for the `VersionNumber`
of Julia itself, and [Version Number Literals](@ref man-version-number-literals)
in the manual.

# Examples
```jldoctest
julia> a = VersionNumber(1, 2, 3)
v"1.2.3"

julia> a >= v"1.2"
true

julia> b = VersionNumber("2.0.1-rc1")
v"2.0.1-rc1"

julia> b >= v"2.0.1"
false
```
"""
struct VersionNumber
    major::VInt
    minor::VInt
    patch::VInt
    prerelease::VerTuple
    build::VerTuple

    function VersionNumber(major::VInt, minor::VInt, patch::VInt,
                           @nospecialize(pre::VerTuple), @nospecialize(bld::VerTuple))
        major >= 0 || throw(ArgumentError("invalid negative major version: $major"))
        minor >= 0 || throw(ArgumentError("invalid negative minor version: $minor"))
        patch >= 0 || throw(ArgumentError("invalid negative patch version: $patch"))
        for ident in pre
            if ident isa Integer
                ident >= 0 || throw(ArgumentError("invalid negative pre-release identifier: $ident"))
            else
                if !occursin(r"^(?:|[0-9a-z-]*[a-z-][0-9a-z-]*)$"i, ident) ||
                    isempty(ident) && !(length(pre)==1 && isempty(bld))
                    throw(ArgumentError("invalid pre-release identifier: $(repr(ident))"))
                end
            end
        end
        for ident in bld
            if ident isa Integer
                ident >= 0 || throw(ArgumentError("invalid negative build identifier: $ident"))
            else
                if !occursin(r"^(?:|[0-9a-z-]*[a-z-][0-9a-z-]*)$"i, ident) ||
                    isempty(ident) && length(bld)!=1
                    throw(ArgumentError("invalid build identifier: $(repr(ident))"))
                end
            end
        end
        new(major, minor, patch, pre, bld)
    end
end
VersionNumber(major::Integer, minor::Integer = 0, patch::Integer = 0,
        pre::Tuple{Vararg{Union{Integer,AbstractString}}} = (),
        bld::Tuple{Vararg{Union{Integer,AbstractString}}} = ()) =
    VersionNumber(VInt(major), VInt(minor), VInt(patch),
        map(x->x isa Integer ? UInt64(x) : String(x), pre),
        map(x->x isa Integer ? UInt64(x) : String(x), bld))

VersionNumber(v::Tuple) = VersionNumber(v...)
VersionNumber(v::VersionNumber) = v

function print(io::IO, v::VersionNumber)
    v == typemax(VersionNumber) && return print(io, "∞")
    print(io, v.major)
    print(io, '.')
    print(io, v.minor)
    print(io, '.')
    print(io, v.patch)
    if !isempty(v.prerelease)
        print(io, '-')
        join(io, v.prerelease,'.')
    end
    if !isempty(v.build)
        print(io, '+')
        join(io, v.build,'.')
    end
end
show(io::IO, v::VersionNumber) = print(io, "v\"", v, "\"")

Broadcast.broadcastable(v::VersionNumber) = Ref(v)

const VERSION_REGEX = r"^
    v?                                      # prefix        (optional)
    (\d+)                                   # major         (required)
    (?:\.(\d+))?                            # minor         (optional)
    (?:\.(\d+))?                            # patch         (optional)
    (?:(-)|                                 # pre-release   (optional)
    ([a-z][0-9a-z-]*(?:\.[0-9a-z-]+)*|-(?:[0-9a-z-]+\.)*[0-9a-z-]+)?
    (?:(\+)|
    (?:\+((?:[0-9a-z-]+\.)*[0-9a-z-]+))?    # build         (optional)
    ))
$"ix

function split_idents(s::AbstractString)
    idents = eachsplit(s, '.')
    pidents = Union{UInt64,String}[occursin(r"^\d+$", ident) ? parse(UInt64, ident) : String(ident) for ident in idents]
    return tuple(pidents...)::VerTuple
end

function tryparse(::Type{VersionNumber}, v::AbstractString)
    v == "∞" && return typemax(VersionNumber)
    m = match(VERSION_REGEX, String(v)::String)
    m === nothing && return nothing
    major, minor, patch, minus, prerl, plus, build = m.captures
    major = parse(VInt, major::AbstractString)
    minor = minor !== nothing ? parse(VInt, minor) : VInt(0)
    patch = patch !== nothing ? parse(VInt, patch) : VInt(0)
    if prerl !== nothing && !isempty(prerl) && prerl[1] == '-'
        prerl = prerl[2:end] # strip leading '-'
    end
    prerl = prerl !== nothing ? split_idents(prerl) : minus !== nothing ? ("",) : ()
    build = build !== nothing ? split_idents(build) : plus  !== nothing ? ("",) : ()
    return VersionNumber(major, minor, patch, prerl::VerTuple, build::VerTuple)
end

function parse(::Type{VersionNumber}, v::AbstractString)
    ver = tryparse(VersionNumber, v)
    ver === nothing && throw(ArgumentError("invalid version string: $v"))
    return ver
end

VersionNumber(v::AbstractString) = parse(VersionNumber, v)

"""
    @v_str

String macro used to parse a string to a [`VersionNumber`](@ref).

# Examples
```jldoctest
julia> v"1.2.3"
v"1.2.3"

julia> v"2.0.1-rc1"
v"2.0.1-rc1"
```
"""
macro v_str(v); VersionNumber(v); end

function typemax(::Type{VersionNumber})
    ∞ = typemax(VInt)
    VersionNumber(∞, ∞, ∞, (), ("",))
end

typemin(::Type{VersionNumber}) = v"0-"

ident_cmp(a::Integer, b::Integer) = cmp(a, b)
ident_cmp(a::Integer, b::String ) = isempty(b) ? +1 : -1
ident_cmp(a::String,  b::Integer) = isempty(a) ? -1 : +1
ident_cmp(a::String,  b::String ) = cmp(a, b)

function ident_cmp(@nospecialize(A::VerTuple), @nospecialize(B::VerTuple))
    for (a, b) in Iterators.Zip{Tuple{VerTuple,VerTuple}}((A, B))
        c = ident_cmp(a, b)
        (c != 0) && return c
    end
    length(A) < length(B) ? -1 :
    length(B) < length(A) ? +1 : 0
end

function ==(a::VersionNumber, b::VersionNumber)
    (a.major != b.major) && return false
    (a.minor != b.minor) && return false
    (a.patch != b.patch) && return false
    (ident_cmp(a.prerelease, b.prerelease) != 0) && return false
    (ident_cmp(a.build, b.build) != 0) && return false
    return true
end

issupbuild(v::VersionNumber) = length(v.build)==1 && isempty(v.build[1])

function isless(a::VersionNumber, b::VersionNumber)
    (a.major < b.major) && return true
    (a.major > b.major) && return false
    (a.minor < b.minor) && return true
    (a.minor > b.minor) && return false
    (a.patch < b.patch) && return true
    (a.patch > b.patch) && return false
    (!isempty(a.prerelease) && isempty(b.prerelease)) && return true
    (isempty(a.prerelease) && !isempty(b.prerelease)) && return false
    c = ident_cmp(a.prerelease,b.prerelease)
    (c < 0) && return true
    (c > 0) && return false
    (!issupbuild(a) && issupbuild(b)) && return true
    (issupbuild(a) && !issupbuild(b)) && return false
    c = ident_cmp(a.build,b.build)
    (c < 0) && return true
    return false
end

function hash(v::VersionNumber, h::UInt)
    h ⊻= 0x8ff4ffdb75f9fede % UInt
    h = hash(v.major, h)
    h = hash(v.minor, h)
    h = hash(v.patch, h)
    h = hash(v.prerelease, ~h)
    h = hash(v.build, ~h)
end

lowerbound(v::VersionNumber) = VersionNumber(v.major, v.minor, v.patch, ("",), ())
upperbound(v::VersionNumber) = VersionNumber(v.major, v.minor, v.patch, (), ("",))

thispatch(v::VersionNumber) = VersionNumber(v.major, v.minor, v.patch)
thisminor(v::VersionNumber) = VersionNumber(v.major, v.minor, 0)
thismajor(v::VersionNumber) = VersionNumber(v.major, 0, 0)

nextpatch(v::VersionNumber) = v < thispatch(v) ? thispatch(v) : VersionNumber(v.major, v.minor, v.patch+1)
nextminor(v::VersionNumber) = v < thisminor(v) ? thisminor(v) : VersionNumber(v.major, v.minor+1, 0)
nextmajor(v::VersionNumber) = v < thismajor(v) ? thismajor(v) : VersionNumber(v.major+1, 0, 0)

## julia version info

"""
    VERSION

A [`VersionNumber`](@ref) object describing which version of Julia is in use. See also
[Version Number Literals](@ref man-version-number-literals).
"""
const VERSION = try
    ver = VersionNumber(VERSION_STRING)
    if !isempty(ver.prerelease) && !GIT_VERSION_INFO.tagged_commit
        if GIT_VERSION_INFO.build_number >= 0
            ver = VersionNumber(ver.major, ver.minor, ver.patch, (ver.prerelease..., GIT_VERSION_INFO.build_number), ver.build)
        else
            println("WARNING: no build number found for pre-release version")
            ver = VersionNumber(ver.major, ver.minor, ver.patch, (ver.prerelease..., "unknown"), ver.build)
        end
    elseif GIT_VERSION_INFO.build_number > 0
        println("WARNING: ignoring non-zero build number for VERSION")
    end
    ver
catch e
    println("while creating Base.VERSION, ignoring error $e")
    VersionNumber(0)
end

const libllvm_version = if endswith(libllvm_version_string, "jl")
    # strip the "jl" SONAME suffix (JuliaLang/julia#33058)
    # (LLVM does never report a prerelease version anyway)
    VersionNumber(libllvm_version_string[1:end-2])
else
    VersionNumber(libllvm_version_string)
end

libllvm_path() = ccall(:jl_get_libllvm, Any, ())
