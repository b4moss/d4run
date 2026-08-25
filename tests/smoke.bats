@test "init-project.sh is readable" {
  [ -f init-project.sh ]
}

@test "init-project.sh has shebang" {
  run head -n 1 init-project.sh
  [[ "$output" == "#!"* ]]
}
