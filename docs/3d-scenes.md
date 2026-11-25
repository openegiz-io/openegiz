# 3D Scenes

The Unity Grafana panel loads a compiled WebGL scene. Prepare the scene, serve the files where viewers' browsers can reach them, and connect the panel to Twin data.

## Prepare the build

In Unity, target WebGL and set **Player Settings → Publishing Settings → Compression Format** to **Disabled**. The panel needs the four uncompressed files `*.loader.js`, `*.framework.js`, `*.data`, and `*.wasm`. Use names without spaces or URL-encode spaces as `%20`. Set `WebGLInput.captureAllKeyboardInput = false` in an always-active script so the dashboard keeps its keyboard input.

From the repository root, copy your files into `build/` with `make copy-build SRC=/path/to/unity-output`. This replaces existing files with the four matching extensions. To try a sample scene, use `make unity-demo`, which downloads an approximately 88 MB build.

## Serve the files

| Deployment | Upload | Browser URL |
|---|---|---|
| Compose Dev Profile | Copy into `build/` | `http://localhost:8090/build/<filename>` |
| Compose Production Profile | Copy into `build/` | `https://twins.example.com/build/<filename>` |
| Kubernetes | Copy into `build/`, then run `make upload-build RELEASE_NAME=plant NAMESPACE=twins` | `https://scenes.example.com/build/<filename>` or the equivalent port-forward URL |

Compose serves the local directory. Helm uploads files to the 3D Scene server's PVC, so they survive pod restarts and upgrades. Paste each complete file URL into Grafana. Keep the scene URLs on HTTPS if the dashboard uses HTTPS, and make sure the viewing browser trusts the certificate.

## Connect the panel to Twins

1. Add a visualization of type **Unity**. Under **Unity model**, choose **External links** and paste the four file URLs.
2. Add the following query to return a `thingId` column and a row per Twin.

   ```flux
   import "types"

   from(bucket: "default")
     |> range(start: -1m)
     |> filter(fn: (r) => r["_measurement"] == "mqtt_consumer" and r["_field"] =~ /_properties_value$/)
     |> filter(fn: (r) => types.isNumeric(v: r._value))
     |> group(columns: ["thingId", "_field"])
     |> last()
     |> group(columns: ["thingId"])
     |> pivot(rowKey: ["thingId"], columnKey: ["_field"], valueColumn: "_value")
   ```

   For text fields, use a separate query with `types.isType(v: r._value, type: "string")` in place of the numeric filter.
3. Under **Send data to Unity**, choose **Send data to GameObjects by ID column** with ID column `thingId` and function `SetValues`.

Name each active GameObject after its Twin ID, such as `org.openegiz:oven-01`. The panel calls `SendMessage(<thingId>, "SetValues", json)` on dashboard refresh. The receiver takes a JSON string with a `series` object such as `{"series":{"value_temperature_properties_value":182.5}}`. Multiple rows with overlapping columns can make `series` an array. Use a JSON parser that supports dynamic property names, such as Newtonsoft JSON. If the receiver is missing, check the browser console and verify the GameObject name and method. The panel sends frames from every query and skips sending while in panel edit mode.

To filter a dashboard after selecting a scene object, map a scene event to an existing dashboard variable under **Receive data from Unity**. Add the following event dispatcher to a WebGL JavaScript plugin such as `Assets/Plugins/WebGL/Grafana.jslib`.

```javascript
mergeInto(LibraryManager.library, {
  SelectTwin: function (id) {
    window.dispatchReactUnityEvent("SelectTwin", UTF8ToString(id));
  }
});
```

Call it from C# through `[DllImport("__Internal")] static extern void SelectTwin(string id);`. Grafana sets the mapped dashboard variable to the event's first argument.
