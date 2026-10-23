const React = require('react');
const {AppRegistry, View, Text} = require('react-native');
const Ansight = require('@ansight/react-native');
const {AnsightPencil, usePencilSurface} = require('@ansight/react-native-pencil');
const observations = [];
function App() {
  const ref = React.useRef(null);
  const [count,setCount] = React.useState(0);
  const receive = phase => event => {
    const e=event.nativeEvent;
    observations.push({phase,x:e.locationX,y:e.locationY,pressure:e.pressure,tiltX:e.tiltX,tiltY:e.tiltY,twist:e.twist,pencil:e.ansightPencil});
    setCount(observations.length);
  };
  const bindings=usePencilSurface('drawing-canvas',ref,{
    onPointerDown:receive('down'),onPointerMove:receive('move'),onPointerUp:receive('up'),onPointerCancel:receive('cancel'),
    onPointerEnter:receive('hoverEnter'),onPointerLeave:receive('hoverExit'),
  });
  return React.createElement(View,{...bindings,ref,style:{flex:1,backgroundColor:'#0c1727'}},
    React.createElement(Text,{pointerEvents:'none',style:{color:'white',fontSize:22,margin:50}},`REACT NATIVE / PENCIL\n${count} handler events\n${JSON.stringify(observations.at(-1)) || 'Waiting'}`),
    ...observations.filter(e=>['down','move'].includes(e.phase)&&e.pressure>0).map((e,i)=>React.createElement(View,{key:i,pointerEvents:'none',style:{position:'absolute',left:e.x-3,top:e.y-3,width:6+e.pressure*6,height:6+e.pressure*6,borderRadius:8,backgroundColor:'#5bf0c3'}})));
}
AppRegistry.registerComponent('PencilReactNative',()=>App);
(async()=>{
  const options=Ansight.createOptionsBuilder().withAnsightDefaults().withTouchCapture()
    .withSessionJpegCapture({intervalMilliseconds:250}).withHostConnectionDiscoveryPort(49432).withPlugin(AnsightPencil).build();
  await Ansight.initializeAndActivate(options);
  await Ansight.registerTool({id:'pencil.observations',name:'Read Pencil handler observations',category:'test',policy:'read',argumentsSchema:{type:'object',properties:{}}},async()=>({success:true,result:{observations}})).ready;
})().catch(error=>console.error('Pencil initialization failed',error));
