# merge(baseline; machine): objects recurse, arrays union, scalars machine wins
def merge($a; $b):
  if ($a|type) == "object" and ($b|type) == "object" then
    reduce (($a|keys) + ($b|keys) | unique[]) as $k ({}; .[$k] = merge($a[$k]; $b[$k]))
  elif ($a|type) == "array" and ($b|type) == "array" then ($a + $b | unique)
  elif $b == null then $a
  else $b end;
merge(.[0]; .[1])
