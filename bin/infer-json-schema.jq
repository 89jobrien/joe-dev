# Infer a practical JSON Schema from one sample document.

def normalized_type($types):
  ($types | sort | unique) as $u
  | if ($u | length) == 1 then $u[0] else $u end;

def intersect($a; $b):
  [($a // [])[] as $item | select(($b // []) | index($item))];

def merge_schema($a; $b):
  if $a == null then $b
  elif $b == null then $a
  else
    ((if ($a | has("type")) then ($a.type | if type == "array" then . else [.] end) else [] end)
     + (if ($b | has("type")) then ($b.type | if type == "array" then . else [.] end) else [] end)) as $types
    | {type: normalized_type($types)}
      + (if ($types | index("object")) != null then
           {
             properties:
               ((($a.properties // {} | keys_unsorted) + ($b.properties // {} | keys_unsorted) | unique) as $keys
                | reduce $keys[] as $key
                    ({};
                     .[$key] = merge_schema(($a.properties[$key] // null); ($b.properties[$key] // null)))),
             required: intersect(($a.required // []); ($b.required // [])),
             additionalProperties: false
           }
         else
           {}
         end)
      + (if ($types | index("array")) != null then
           {
             items: merge_schema(($a.items // null); ($b.items // null))
           }
         else
           {}
         end)
  end;

def infer_schema:
  if type == "object" then
    {
      type: "object",
      properties: (to_entries | map({key, value: (.value | infer_schema)}) | from_entries),
      required: (keys_unsorted | sort),
      additionalProperties: false
    }
  elif type == "array" then
    {
      type: "array",
      items: (reduce .[] as $item (null; merge_schema(.; ($item | infer_schema))) // {})
    }
  else
    {type: type}
  end;

(. | infer_schema)
| . + {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "title": "Inferred schema",
    "description": "Generated from sample JSON with jq."
  }
