#!/bin/bash
# Renders the earcon pack into ~/.claude/sounds/pack. Rerun after changing a recipe.
# Style: soft sines with a quick bell partial, 10-15 ms attack and exponential fades, pentatonic pitches so nothing
# clashes, a light echo for space.
cd "$(dirname "$0")" && mkdir -p pack && cd pack

# n HZ START TAU GAIN [BELL]: a note with octave and a bell partial that dies in 40 ms
n() { echo "if(gte(t,$2),$4*min(1,(t-$2)/0.012)*exp(-(t-$2)/$3)*(sin(2*PI*$1*(t-$2))+0.25*sin(4*PI*$1*(t-$2))+${5:-0.12}*sin(8*PI*$1*(t-$2))*exp(-(t-$2)/0.04)),0)"; }
# s F0 F1 START DUR GAIN: a glide from F0 to F1 under a smooth swell
s() { echo "if(between(t,$3,$3+$4),$5*sin(PI*(t-$3)/$4)^2*sin(2*PI*($1*(t-$3)+($2-$1)*(t-$3)^2/(2*$4))),0)"; }
# p HZ START GAIN: a bubble pop, pitch falls fast
p() { echo "if(gte(t,$2),$3*exp(-(t-$2)/0.03)*sin(2*PI*($1*(t-$2)-$1*1.5*(t-$2)^2)),0)"; }

mk() { # NAME DURATION LOUDNESS EXPR
  ffmpeg -loglevel error -y -f lavfi -i "aevalsrc='$4':s=48000:d=$2" \
    -af "aecho=0.8:0.5:70|130:0.16|0.08,afade=t=out:st=$(awk "BEGIN{print $2-0.06}"):d=0.06" -ar 48000 "$1.wav"
}

# Thinking: one beat of a slow pulse, looped while Claude works
mk think-heartbeat 0.7 -34 "$(n 196 0 0.07 0.5 0) + $(n 146.83 0.16 0.11 0.6 0)"
mk think-marimba   0.7 -34 "$(n 392 0 0.06 0.5 0.3) + $(n 293.66 0.17 0.09 0.5 0.3)"
mk think-orb       1.2 -36 "$(s 220 330 0 1.1 0.4) + $(s 330 440 0 1.1 0.15)"
mk think-droplet   0.6 -35 "$(p 880 0 0.5) + $(p 660 0.18 0.4)"
mk think-pentatonic 0.9 -35 "$(n 523.25 0 0.08 0.4 0.2) + $(n 659.25 0.15 0.08 0.35 0.2) + $(n 783.99 0.3 0.12 0.3 0.2)"

# k START GAIN: a kick that drops from 140 to 48 Hz in 40 ms and fades over 180 ms
k() { echo "if(gte(t,$1),$2*min(1,(t-$1)/0.004)*exp(-(t-$1)/0.06)*(sin(2*PI*(48*(t-$1)+92*0.04*(1-exp(-(t-$1)/0.04))))+0.35*sin(4*PI*(48*(t-$1)+92*0.04*(1-exp(-(t-$1)/0.04))))),0)"; }
mk think-pulse 0.7 0 "$(k 0 0.5) + $(k 0.2 0.7)"

# House bar: 122 BPM, soft kick on every beat, open hats on the offbeats, round sine bass
# on the offbeats, one minor-ninth electric piano stab on steps 3 and 11, low-passed at 3.8 kHz. Loops with no gap.
house() {
  local q=0.4918 st=0.12295 drums="" hats="" i
  for i in 0 1 2 3; do drums+="$(k $(awk "BEGIN{print $i*$q}") 0.45) + $(n 110 $(awk "BEGIN{print $i*$q+$q/2}") 0.09 0.2 0) + "
    hats+="if(gte(t,$(awk "BEGIN{print $i*$q+$q/2}")),(2*random(0)-1)*0.25*exp(-(t-$(awk "BEGIN{print $i*$q+$q/2}"))/0.05),0) + "; done
  local stab="" s h; for s in 3 11; do for h in 220 261.63 329.63 392 493.88; do stab+="$(n $h $(awk "BEGIN{print $s*$st}") 0.22 0.07 0) + "; done; done
  ffmpeg -loglevel error -y -f lavfi -i "aevalsrc='${drums}${stab}0':s=48000:d=1.967" -ar 48000 house-a.wav
  ffmpeg -loglevel error -y -f lavfi -i "aevalsrc='${hats}0':s=48000:d=1.967" -af highpass=f=7000 -ar 48000 house-b.wav
  sox -m house-a.wav house-b.wav think-house.wav lowpass 3800 && rm house-a.wav house-b.wav
}
house

# Step: one per tool call
mk tick-soft   0.2 -30 "$(n 1046.5 0 0.035 0.5 0)"
mk tick-wood   0.2 -29 "$(n 784 0 0.025 0.5 0.4)"
mk tick-bubble 0.2 -30 "$(p 1200 0 0.6)"
mk tick-glass  0.3 -31 "$(n 1567.98 0 0.05 0.4 0.3)"
mk tick-low    0.2 -29 "$(n 523.25 0 0.03 0.5 0.1)"

# Done: the reply is finished
mk done-badum    1.0 -20 "$(n 587.33 0 0.18 0.5) + $(n 880 0.13 0.3 0.45)"
mk done-arpeggio 1.1 -21 "$(n 523.25 0 0.15 0.4) + $(n 659.25 0.09 0.15 0.4) + $(n 783.99 0.18 0.3 0.4)"
mk done-swoosh   0.6 -22 "$(s 500 1100 0 0.35 0.5) + $(n 1046.5 0.3 0.15 0.25)"
mk done-warm     1.6 -21 "$(n 196 0 0.4 0.5) + $(n 293.66 0.28 0.5 0.45)"
mk done-bell     1.4 -22 "$(n 783.99 0 0.45 0.4 0.3) + $(n 1174.66 0 0.35 0.15 0.3)"

# Fail: a step or the turn failed
mk fail-fall  1.0 -22 "$(n 440 0 0.18 0.5) + $(n 293.66 0.14 0.35 0.45)"
mk fail-thud  0.6 -22 "$(n 146.83 0 0.08 0.6 0) + $(n 130.81 0.14 0.12 0.6 0)"
mk fail-minor 1.1 -23 "$(n 587.33 0 0.15 0.4) + $(n 493.88 0.12 0.15 0.4) + $(n 440 0.24 0.3 0.4)"

# Needs you: a permission prompt or a question
mk chime-atlas    1.6 -21 "$(n 659.25 0 0.5 0.4) + $(n 987.77 0 0.4 0.18) + $(n 1318.5 0 0.3 0.1)"
mk chime-knock    0.6 -21 "$(n 392 0 0.05 0.6 0.4) + $(n 392 0.16 0.05 0.6 0.4)"
mk chime-rise     1.0 -21 "$(n 523.25 0 0.2 0.4) + $(n 659.25 0.1 0.2 0.4) + $(n 783.99 0.2 0.2 0.4) + $(n 1046.5 0.3 0.35 0.4)"
mk chime-doorbell 1.4 -21 "$(n 659.25 0 0.4 0.5) + $(n 523.25 0.35 0.5 0.5)"

# Send: you submitted a prompt
mk send-swoosh 0.5 -26 "$(s 400 900 0 0.3 0.5)"
mk send-pop    0.3 -27 "$(p 700 0 0.6)"
ls *.wav | wc -l

# Level every sound to the same loudest 50 ms (RMS peak) so none jumps out.
for f in *.wav; do
  read -r rms pk < <(sox "$f" -t dat - | awk 'NR>2{x=$2; v=x<0?-x:x; if(v>p)p=v; q[NR%2400]=x*x; s+=x*x-o[NR%2400]; o[NR%2400]=x*x; if(s>m)m=s} END{print 10*log(m/2400)/log(10), 20*log(p)/log(10)}')
  sox "$f" t.wav gain "$(awk "BEGIN{g=-20-($rms); c=-1-($pk); print (g<c?g:c)}")" && mv t.wav "$f"
done

# Backchannel: a soft rising "mm-hm" the helper hums when the user pauses mid-thought.
cd "$(dirname "$0")/pack"
ffmpeg -loglevel error -y -f lavfi -i "aevalsrc='0.4*min(1,t/0.03)*exp(-t/0.12)*sin(2*PI*196*t)*lt(t,0.18) + if(gte(t,0.2),0.4*min(1,(t-0.2)/0.03)*exp(-(t-0.2)/0.2)*sin(2*PI*247*(t-0.2)),0)':s=48000:d=0.6" -af "lowpass=f=1200,afade=t=out:st=0.5:d=0.1" -ar 48000 mm.wav
sox mm.wav t.wav gain -n -26 && mv t.wav mm.wav
