import React, {useRef} from 'react';
import {View, type ViewProps} from 'react-native';
import {usePencilSurface, type AnsightPencilEvent} from '@ansight/react-native-pencil';
export function DrawingSurface({children,...handlers}:ViewProps) {
  const canvas=useRef<View>(null);
  const bindings=usePencilSurface('drawing-canvas',canvas,handlers);
  return <View ref={canvas} {...bindings}>{children}</View>;
}
export function readRoll(event:AnsightPencilEvent) { return event.nativeEvent.ansightPencil?.rollRadians; }
