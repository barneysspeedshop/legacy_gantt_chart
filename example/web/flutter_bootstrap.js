{{flutter_js}}
{{flutter_build_config}}

const hostElement = document.getElementById('flutter_target');
const config = {
  canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).toString(),
  ...(hostElement ? {hostElement} : {}),
};
_flutter.loader.load({config});
