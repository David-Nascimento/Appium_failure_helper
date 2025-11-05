# Guia de Integração com Jenkins (CI/CD)

Este guia mostra como configurar o job no Jenkins para publicar automaticamente os relatórios HTML gerados pela `AppiumFailureHelper` a cada build com falha.

## Visão Geral

A integração é simples e não requer nenhuma configuração complexa na GEM. A própria GEM já está pré-configurada para gerar um relatório estável para o Jenkins.

Quando um teste falha, a GEM automaticamente:
1.  Gera o relatório detalhado em uma pasta com timestamp (ex: `reports_failure/failure_...`).
2.  Copia o arquivo `report.html` principal para uma pasta fixa na raiz do projeto: `ci_failure_report/index.html`.

O seu trabalho no Jenkins é apenas instalar um plugin e apontá-lo para essa pasta.

---

### Passo 1: Instalar o Plugin no Jenkins

1.  No seu painel do Jenkins, vá para `Gerenciar Jenkins` > `Plugins`.
2.  Na aba `Disponíveis`, procure por `HTML Publisher`.
3.  Instale o plugin e reinicie o Jenkins, se solicitado.

---

### Passo 2: Adicionar a Pasta ao `.gitignore`

Para evitar que os relatórios de CI sejam comitados no seu repositório Git, adicione a pasta de relatórios ao seu arquivo `.gitignore` na raiz do projeto:

```
# .gitignore

# Relatórios de falha locais
reports_failure/

# Relatório estável para o Jenkins
ci_failure_report/
```

---

### Passo 3: Configurar seu Job no Jenkins

Abaixo estão as duas formas mais comuns de configurar o job.

#### Opção A: Projeto Freestyle (Configuração pela UI)

1.  Abra a **Configuração** do seu Job.
2.  Vá até a seção **"Ações de pós-build"** (Post-build Actions).
3.  Clique em **"Adicionar ação de pós-build"** e selecione **"Publish HTML reports"**.
4.  Preencha os campos da seguinte forma:
    * **HTML directory to archive:** `ci_failure_report`
    * **Index page[s]:** `index.html`
    * **Report title:** `Diagnóstico de Falha`
5.  Salve.

#### Opção B: Projeto Pipeline (Configuração via `Jenkinsfile`)

Se você usa um `Jenkinsfile`, adicione o passo `publishHTML` no seu bloco `post { failure { ... } }`. Isso garante que o relatório só seja publicado se o build falhar.

```groovy
// Jenkinsfile

pipeline {
    agent any
    stages {
        stage('Test') {
            steps {
                // Roda seus testes. O 'catchError' garante que o pipeline continue
                // para que as ações de pós-build possam ser executadas.
                catchError(buildResult: 'FAILURE', stageResult: 'FAILURE') {
                    sh 'bundle exec cucumber'
                }
            }
        }
    }
    post {
        // Executa APENAS SE O BUILD FALHAR
        failure {
            echo "Build falhou. Publicando relatório de diagnóstico da GEM..."
            
            publishHTML(
                target: [
                    allowMissing: true,         // Não falha o build se a pasta não existir
                    directory: 'ci_failure_report',  // A pasta que a GEM cria
                    files: 'index.html',        // O arquivo HTML padrão
                    keepAll: true,              // Mantém o histórico de relatórios
                    reportDir: 'DiagnosticoFalha', // O nome na URL do Jenkins
                    reportName: 'Diagnóstico de Falha' // O nome do link no menu
                ]
            )
        }
        
        always {
            // (Opcional, mas recomendado) Arquiva os relatórios do Allure
            // allure(results: [[path: 'logs/allure-results']])
            
            // Limpa o workspace para a próxima execução
            cleanWs()
        }
    }
}
```

---

### Resultado

Após a próxima execução falha no Jenkins, um novo link chamado **"Diagnóstico de Falha"** aparecerá no menu esquerdo do build. Ao clicar, o relatório HTML interativo da sua GEM será exibido diretamente na interface do Jenkins.