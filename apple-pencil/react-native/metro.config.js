const path = require('node:path');
const {getDefaultConfig, mergeConfig} = require('@react-native/metro-config');
module.exports = mergeConfig(getDefaultConfig(__dirname), {
  watchFolders: ['react-native','react-native-pencil','pencil-runtime'].map(name => path.resolve(__dirname, '../../../ansight/ansight-sdk/src', name)),
  resolver: { disableHierarchicalLookup: true, nodeModulesPaths: [path.resolve(__dirname, 'node_modules')] },
});
