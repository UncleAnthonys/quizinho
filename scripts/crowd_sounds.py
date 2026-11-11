"""The referee's whistle and the crowd (cheer, groan, "ooh").

The crowd is a hundred-odd synthesised voices — each a jittery buzz through
vowel formants, with its own pitch, throat and timing — plus claps and a
stadium-ish reverb, rather than filtered noise. The whistle is a pea whistle:
an uneven rattle (the pea) on a ~3 kHz tone with breath. Called from
generate_sounds.py; needs numpy and scipy.
"""
import pathlib
import wave

import numpy as np
from scipy import signal
SR=44_100
rng=np.random.default_rng(11)

def save(out,name,x,gain=0.9):
    x=x/(np.max(np.abs(x))+1e-9)*gain
    with wave.open(str(out/f"{name}.wav"),"wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x*32767).astype(np.int16).tobytes())

def bp(x,lo,hi,order=2):
    sos=signal.butter(order,[lo,hi],btype='band',fs=SR,output='sos'); return signal.sosfilt(sos,x)
def lp(x,f,order=2):
    sos=signal.butter(order,f,btype='low',fs=SR,output='sos'); return signal.sosfilt(sos,x)

def reverb(x,rt=1.4,mix=0.3,pre=0.02):
    n=int(SR*rt); tt=np.arange(n)/SR
    ir=rng.normal(size=n)*np.exp(-6.9*tt/rt); ir=lp(ir,4500); ir[:int(SR*pre)]=0
    wet=signal.fftconvolve(x,ir)[:len(x)]
    wet=wet/(np.max(np.abs(wet))+1e-9)*np.max(np.abs(x))
    return (1-mix)*x+mix*wet

FORMANTS={'ah':[(800,80),(1200,90),(2500,120)],'ay':[(600,70),(1900,100),(2600,120)],
          'oh':[(500,70),(900,80),(2400,120)],'oo':[(350,60),(800,80),(2300,120)],'uh':[(600,80),(1050,90),(2400,120)]}

def formant(x,vowel):
    y=np.zeros_like(x)
    scale=rng.uniform(0.85,1.18)   # every throat is different
    for i,(f,bw) in enumerate(FORMANTS[vowel]):
        f=f*scale*rng.uniform(0.95,1.05)
        b,a=signal.iirpeak(f,f/bw,fs=SR); y+=signal.lfilter(b,a,x)*(1.0,0.6,0.25)[i]
    return y

def one_voice(n,f0,contour,vowel,start,att,rel,level):
    """A shouting voice: jittery glottal buzz through vowel formants."""
    k=np.arange(n)/n
    jit=1+0.02*lp(rng.normal(size=n),8)*20
    vib=1+0.012*np.sin(2*np.pi*rng.uniform(4,6.5)*np.arange(n)/SR+rng.uniform(0,6))
    f=f0*contour(k)*jit*vib
    ph=np.cumsum(f)/SR
    src=2*(ph%1)-1+0.15*rng.normal(size=n)   # buzz + breath
    v=formant(src,vowel)
    e=np.zeros(n); s=int(start*SR); a=max(1,int(att*SR)); r=max(1,int(rel*SR))
    e[s:]=1; e[s:s+a]=np.linspace(0,1,min(a,n-s)) if s<n else 0
    e[-r:]*=np.linspace(1,0,r)
    return v*e*level

def crowd(n,count,vowels,contour,start_spread,att,rel,f0s=((105,175),(190,300))):
    mix=np.zeros(n)
    for i in range(count):
        lo,hi=f0s[i%3==0]
        mix+=one_voice(n,rng.uniform(lo,hi),contour,vowels[i%len(vowels)],rng.uniform(0,start_spread),
                       rng.uniform(*att),rng.uniform(*rel),rng.uniform(0.4,1.0))
    return mix/np.max(np.abs(mix))

def claps(n,count,t0,t1):
    x=np.zeros(n); L=int(0.03*SR); e=np.exp(-np.arange(L)/SR*180)
    for _ in range(count):
        s=int(rng.uniform(t0,t1)*SR)
        if s+L<n: x[s:s+L]+=bp(rng.normal(size=L),900,4200)*e*rng.uniform(0.3,1)
    return x/np.max(np.abs(x))

def cheer():
    n=int(SR*2.6)
    v=crowd(n,140,['ay','ah','oh','ah'],lambda k:1+0.18*np.minimum(1,k*4)-0.06*k,0.35,(0.08,0.25),(0.5,1.0))
    c=claps(n,420,0.35,2.4)
    bed=bp(rng.normal(size=n),250,3000)
    k=np.linspace(0,1,n); sw=np.minimum(1,k*5)*np.minimum(1,(1-k)*2.2)
    return reverb((v+0.35*c+0.12*bed)*sw,1.6,0.35)

def groan():
    n=int(SR*1.7)
    v=crowd(n,110,['uh','oh','ah'],lambda k:1.05-0.2*k,0.15,(0.15,0.35),(0.5,0.8),((90,150),(170,250)))
    bed=lp(rng.normal(size=n),700)
    k=np.linspace(0,1,n); sw=np.minimum(1,k*4)*np.minimum(1,(1-k)*2.5)
    return reverb((v+0.1*bed)*sw,1.5,0.35)

def ooh():
    n=int(SR*1.6)
    v=crowd(n,110,['oo','oh','oo'],lambda k:1+0.12*np.sin(np.pi*np.minimum(1,k*1.6))-0.15*k**2,0.12,(0.1,0.3),(0.4,0.7))
    k=np.linspace(0,1,n); sw=np.sin(np.pi*k)**0.9
    return reverb(v*sw,1.5,0.35)

def whistle():
    def blast(sec,base):
        n=int(SR*sec); tt=np.arange(n)/SR
        rate=28+3*lp(rng.normal(size=n),3)*30          # the pea's rattle, never quite even
        pea=np.sin(2*np.pi*np.cumsum(rate)/SR)
        rise=np.minimum(1,tt/0.035)
        f=base*(0.9+0.1*rise)+70*pea
        ph=2*np.pi*np.cumsum(f)/SR
        tonal=np.sin(ph)+0.22*np.sin(2*ph)+0.06*np.sin(3*ph)
        am=0.62+0.38*(0.5+0.5*pea)
        breath=bp(rng.normal(size=n),2200,4200)*0.18
        x=(tonal*am+breath)
        e=np.ones(n); a=int(0.008*SR); r=int(0.05*SR); e[:a]=np.linspace(0,1,a); e[-r:]*=np.linspace(1,0,r)
        return x*e
    x=np.concatenate([blast(0.17,3050),np.zeros(int(SR*0.07)),blast(0.62,3000)])
    x=np.concatenate([x,np.zeros(int(SR*0.35))])
    return reverb(x,0.9,0.18,0.01)

def write_all(out: pathlib.Path) -> None:
    out.mkdir(parents=True,exist_ok=True)
    save(out,'whistle',whistle(),0.75); save(out,'cheer',cheer(),0.8); save(out,'groan',groan(),0.7); save(out,'ooh',ooh(),0.75)
