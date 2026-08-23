# Auto-generated fix for R8 missing-class errors coming from a transitive
# dependency that bundles the Mozilla Rhino JS engine (org.mozilla.javascript).
# Rhino optionally uses java.beans.* / javax.script.* — full-JDK-only classes
# that don't exist on Android. These code paths are not exercised at runtime
# in this app, so it's safe to tell R8 to stop resolving them instead of
# failing the build.
-dontwarn java.beans.BeanDescriptor
-dontwarn java.beans.BeanInfo
-dontwarn java.beans.IntrospectionException
-dontwarn java.beans.Introspector
-dontwarn java.beans.PropertyDescriptor
-dontwarn javax.script.ScriptEngineFactory