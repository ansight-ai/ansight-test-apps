import Ansight, { createOptionsBuilder, registerTool } from '@ansight/capacitor';
import { AnsightPencil } from '@ansight/capacitor-pencil';
import './style.css';
const canvas = document.querySelector<HTMLCanvasElement>('#drawing-canvas')!;
const status = document.querySelector<HTMLElement>('#status')!;
canvas.width = window.innerWidth; canvas.height = window.innerHeight;
const ctx = canvas.getContext('2d')!;
const observations: Record<string, unknown>[] = [];
for (const phase of ['pointerdown','pointermove','pointerup','pointercancel','pointerenter','pointerleave']) {
  canvas.addEventListener(phase, event => {
    const e = event as PointerEvent;
    observations.push({phase, pressure:e.pressure, x:e.clientX, y:e.clientY, twist:e.twist, tiltX:e.tiltX, tiltY:e.tiltY, pencil:e.ansightPencil});
    if (phase === 'pointerdown') canvas.setPointerCapture(e.pointerId);
    if (e.buttons) { ctx.fillStyle = '#5bf0c3'; ctx.beginPath(); ctx.arc(e.clientX,e.clientY,2+e.pressure*6,0,Math.PI*2); ctx.fill(); }
    status.textContent = `CAPACITOR / DOM PENCIL\n${observations.length} handler events\n${JSON.stringify(observations.at(-1))}`;
    localStorage.setItem('pencil-observations',JSON.stringify(observations));
  });
}
const options = createOptionsBuilder().withAnsightDefaults().withTouchCapture()
  .withSessionJpegCapture({intervalMilliseconds:250}).withHostConnectionDiscoveryPort(49432).withPlugin(AnsightPencil).build();
await Ansight.initializeAndActivate(options);
AnsightPencil.bindSurface('drawing-canvas',canvas);
await registerTool({id:'pencil.observations',name:'Read Pencil handler observations',policy:'read',category:'test',argumentsSchema:{type:'object',properties:{}}},async()=>({success:true,result:{observations}})).ready;
status.textContent = 'CAPACITOR / DOM PENCIL\nReady; SDK playback ready; capture enabled for verification';
