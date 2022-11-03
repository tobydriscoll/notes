using LinearAlgebra,FFTW

function trig(N)
    @assert(iseven(N), "N must be even")
    h = 2π / N
    x = h * (1:N)
    entry1(k) = k==0 ? 0.0 : 0.5 * (-1)^k * cot(k * h / 2)
    D = [ entry1(mod(i-j, N)) for i in 1:N, j in 1:N ]
    entry2(k) = k==0 ? -π^2 / 3h^2 - 1/6 : -0.5 * (-1)^k / sin(h * k / 2)^2
    D² = [entry2(mod(i-j, N)) for i in 1:N, j in 1:N]  
    return x,D,D² 
end

function triginterp(v)
    N = length(v)
    @assert(iseven(N), "length of data must be even")
    S(x) = mod(x,2π)==0 ? 1 : sin(N*x/2) / (N * tan(x/2)) 
    x = 2π/N * (1:N)
    return function(t)
        sum( v[j]*S(t-x[j]) for j in eachindex(v) )
    end
end

"""
    polyinterp(x, v, w)
    polyinterp(x, v)
    polyinterp(v)

Returns a callable function that applies the barycentric formula with weights in vector `w` to evaluate the interpolant with values given in vector `v` at the points in the vector `x`.

If `w` is not given, it is computed from the defintition.

If `x` and `w` are not given, then it is assumed that the values are given at Chebyshev 2nd-kind points.
"""
function polyinterp(x, v, w)
    return function(t)
        denom = numer = 0
        for i in eachindex(x)
            if t==x[i]
                return v[i]
            else
                s = w[i] / (t-x[i])
                denom += s 
                numer += v[i]*s
            end
        end
        return numer / denom
    end
end

# Weights not given:
function polyinterp(x, v)
    C = 4/(maximum(x) - minimum(x))
    weight(i) = 1 / prod(C*(x[i]-x[j]) for j in eachindex(x) if j != i) 
    w = weight.(eachindex(x))
    return polyinterp(x,v,w)
end

# Values at the Chebyshev points:
function polyinterp(v)
    N = length(v) - 1
    x = [ cos(j*π/N) for j in 0:N ]
    w = [ float((-1)^j) for j in 0:N ]
    w[[1,end]] .*= 0.5
    return polyinterp(x, v, w)
end

function gridinterp(V,xx,yy)
    M,N = size(V) .- 1
    Vx = zeros(length(xx), N+1)
    for j in axes(V,2)
        Vx[:,j] = polyinterp(V[:,j]).(xx)
    end
    VV = zeros(length(xx),length(yy))
    for i in axes(Vx,1)
        VV[i,:] = polyinterp(Vx[i,:]).(yy)
    end
    return VV
end

"""
    cheb(N)

Chebyshev differentiation matrix and grid.
"""
function cheb(N)
    x = [ cos(pi*j/N) for j  in 0:N ]
    c(n) = (n==0) || (n==N) ? 2 : 1
    entry(i,j) = i==j ? 0 : c(i)/c(j) * (-1)^(i+j) / (x[i+1] - x[j+1])
    D = [ entry(i,j) for i in 0:N, j in 0:N ]
    D  = D - diagm(vec(sum(D,dims=2)));    # diagonal entries
    return D, x
end

"""
    chebfft(v)

Differentiate values given at Chebyshev points via the FFT.
"""
function chebfft(v)
    # Simple, not optimal. If v is complex, delete "real" commands.
    N = length(v)-1
    N==0 && return [0.0]
    x = [ cos(π*k/N) for k in 0:N ]
    V = [v; v[N:-1:2]]              # transform x -> theta
    U = real(fft(V))
    W = real(ifft(1im*[0:N-1 ;0; 1-N:-1] .* U))
    w = zeros(N+1)
    @. w[2:N] = -W[2:N]/sqrt(1-x[2:N]^2)    # transform theta -> x
    w[1] = sum( n^2 * U[n+1] for n in 0:N-1 )/N + 0.5N*U[N+1];
    w[N+1] = sum( (-1)^(n+1) * n^2 * U[n+1] for n in 0:N-1 )/N + 0.5N*(-1)^(N+1)*U[N+1];
    return w
end


"""
    chebdct(v)

Differentiate values given at Chebyshev points via the discrete cosine transform.
"""
function chebdct(v)
    N = length(v)-1
    N==0 && return [0.0]
    x = [cos(π*k/N) for k in 0:N]
    a = FFTW.r2r(v,FFTW.REDFT00) / N
    a[[1,end]] .*= 0.5
    b = -(0:N) .* a 
    w = zeros(N+1)
    w[2:N] = FFTW.r2r(-b[2:N],FFTW.RODFT00) ./ (2sqrt.(1 .- x[2:N].^2))
    w[1] = sum( n^2 * a[n+1] for n in 0:N-1 )
    w[N+1] = sum( (-1)^(n+1) * n^2 * a[n+1] for n in 0:N-1 )
    return w
end

"""
    clencurt(N)

Nodes and weights for Clenshaw-Curtis quadrature
"""
function clencurt(N)
    θ = [ pi*i/N for i=0:N ];
    x = cos.(θ);
    w = zeros(N+1);
    ii = 2:N;
    v = ones(N-1);
    if mod(N,2)==0
        w[1] = w[N+1] = 1/(N^2-1);
        for k = 1:N/2-1
            v = v - 2*cos.(2*k*θ[ii]) / (4*k^2-1);
        end
        v = v - cos.(N*θ[ii]) / (N^2-1);
    else
        w[1] = w[N+1] = 1/N^2;
        for k = 1:(N-1)/2
            v = v - 2*cos.(2*k*θ[ii]) / (4*k^2-1);
        end
    end
    w[ii] = 2*v/N;
    return x,w
end

"""
    gauss(N)

Nodes and weights for Gauss quadrature
"""
function gauss(N)
    β = [ .5/sqrt(1-1/(2*i)^2) for i = 1:N-1 ];
    T = diagm(1=>β) + diagm(-1=>β);
    x,V = eigen(T);
    i = sortperm(x);
    w = 2*V[1,i].^2;
    return x[i],w
end
