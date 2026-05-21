resource "aws_ecrpublic_repository" "python_application" {
  repository_name = "idp/${{values.app_name}}"

  catalog_data {
    description = "Python app that displays time"
  }
}

output "repository_name" {
  description = "The name of the ECR public repository"
  value       = aws_ecrpublic_repository.python_application.repository_name
}
