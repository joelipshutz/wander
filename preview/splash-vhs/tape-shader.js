// Analog signal approximation: luma/chroma separation, displaced chroma,
// line-time errors, tape dropout, head-switching noise, and color instability.
function createBrandTapeRenderer(canvas) {
  const gl=canvas.getContext('webgl',{alpha:false,antialias:false,preserveDrawingBuffer:true});
  if(!gl)return null;
  const vert=`attribute vec2 position; varying vec2 uv; void main(){uv=position*.5+.5;gl_Position=vec4(position,0.,1.);}`;
  const frag=`precision highp float;
    varying vec2 uv;uniform sampler2D frame;uniform vec2 resolution;uniform float time;uniform float damage;uniform float motion;uniform vec4 objectBox;
    float noise(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453123);}
    float band(float y,float center,float width){return 1.-smoothstep(width*.36,width,abs(y-center));}
    vec3 yiq(vec3 c){return vec3(dot(c,vec3(.299,.587,.114)),dot(c,vec3(.596,-.274,-.322)),dot(c,vec3(.211,-.523,.312)));}
    vec3 rgb(vec3 c){return vec3(c.x+.956*c.y+.621*c.z,c.x-.272*c.y-.647*c.z,c.x-1.106*c.y+1.703*c.z);}
    void main(){
      float d=damage,t=(time+.17)*motion;float f=floor(t*24.);vec2 p=uv;
      // Launch clock starts at zero. Move the liked source waveform earlier,
      // without slowing it down: .50–.70 s elapsed maps to source 1.68–1.88 s.
      float loopTime=mod(time,8.);float hitA=step(.50,loopTime)*(1.-step(.70,loopTime));float hitB=step(4.55,loopTime)*(1.-step(4.71,loopTime));float hitC=step(6.76,loopTime)*(1.-step(7.01,loopTime));float event=max(hitA,max(hitB,hitC))*motion;
      float faultTime=mix(t,1.68+(loopTime-.50),hitA);float epoch=floor(faultTime*2.);
      float center=.16+.69*noise(vec2(epoch,2.8));// Preserve the Events failure waveform, expressed over this object's extent.
      float objectRow=(p.y-objectBox.y)/objectBox.w;
      float damageBand=band(objectRow,center,.20);
      float fine=(noise(vec2(floor(p.y*resolution.y*.52),f))-.5)*(0.10+d*.26)/resolution.x;
      float wobble=sin(p.y*11.+t*2.1)*(.00015+d*.00028)+sin(p.y*41.-t*4.4)*d*.00010;
      float tear=event*damageBand*(.010+d*.088)*objectBox.z*sin(faultTime*41.);
      float head=(1.-smoothstep(.025,.125,p.y))*(.3+d*.7);
      p.x+=motion*(fine+wobble+tear+head*(noise(vec2(floor(p.y*resolution.y),f))-.5)*d*.012);
      p.y+=motion*event*d*d*.011*objectBox.w*2.5*sin(faultTime*31.);
      vec3 c=texture2D(frame,p).rgb;vec3 l=yiq(c);
      float delay=(.8+d*5.8+event*damageBand*d*9.)/resolution.x;
      vec3 chroma=yiq(texture2D(frame,p+vec2(delay,0.)).rgb)*.44;
      chroma+=yiq(texture2D(frame,p+vec2(delay*2.3,0.)).rgb)*.25;
      chroma+=yiq(texture2D(frame,p+vec2(-delay*.55,0.)).rgb)*.20;
      chroma+=yiq(texture2D(frame,p+vec2(delay*3.8,0.)).rgb)*.11;
      // Hold material density and flecks steady. Only registration/geometry move.
      vec2 cq=chroma.yz;
      float materialFrame=13.;
      float grain=noise(floor(p*resolution*.85)+vec2(materialFrame,17.))-.5;
      float dust=noise(floor(p*resolution*vec2(.63,.73))+vec2(materialFrame*.91,41.));
      float speck=step(.9990-d*.0006,dust)*motion;
      float darkSpeck=step(dust,.0006+d*.0007)*motion;
      float luminance=l.x;
      luminance+=grain*(.009+d*.022);
      luminance*=1.-d*.10*(.5+.5*sin(p.y*resolution.y*3.14159));
      vec3 outputColor=rgb(vec3(luminance,cq));
      // Sparse short horizontal dropout streaks: bright dusty traces and dim gaps.
      float streak=step(.995-d*.002,noise(vec2(floor(p.y*resolution.y*.7),materialFrame*.38)))*motion;
      float span=band(p.x,noise(vec2(floor(p.y*resolution.y),materialFrame*.38+3.)),.03+d*.15);
      outputColor+=streak*span*(.045+d*.14);
      outputColor+=speck*(.18+d*.20);outputColor*=1.-darkSpeck*(.32+d*.38);
      outputColor+=head*(noise(vec2(floor(p.x*resolution.x),floor(p.y*resolution.y)+materialFrame))-.5)*d*.052;
      gl_FragColor=vec4(clamp(outputColor,0.,1.),1.);
    }`;
  function shader(type,src){const s=gl.createShader(type);gl.shaderSource(s,src);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw new Error(gl.getShaderInfoLog(s));return s;}
  const program=gl.createProgram();gl.attachShader(program,shader(gl.VERTEX_SHADER,vert));gl.attachShader(program,shader(gl.FRAGMENT_SHADER,frag));gl.linkProgram(program);if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw new Error(gl.getProgramInfoLog(program));gl.useProgram(program);
  const buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]),gl.STATIC_DRAW);const pos=gl.getAttribLocation(program,'position');gl.enableVertexAttribArray(pos);gl.vertexAttribPointer(pos,2,gl.FLOAT,false,0,0);
  const texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,texture);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,true);
  const u=Object.fromEntries(['resolution','time','damage','motion','objectBox'].map(n=>[n,gl.getUniformLocation(program,n)]));
  return (image,t,d,still,objectBox)=>{gl.viewport(0,0,canvas.width,canvas.height);gl.useProgram(program);gl.bindTexture(gl.TEXTURE_2D,texture);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,image);gl.uniform2f(u.resolution,canvas.width,canvas.height);gl.uniform1f(u.time,t);gl.uniform1f(u.damage,d);gl.uniform1f(u.motion,still?0:1);gl.uniform4f(u.objectBox,...objectBox);gl.drawArrays(gl.TRIANGLES,0,6);};
}
