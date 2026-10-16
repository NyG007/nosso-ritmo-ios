# Validação

## Testes automáticos

`swift test --parallel` executa testes do pacote de domínio:

- Semana começando na segunda-feira; recorrências diárias e semanais; limites exclusivos.
- Cancelamento de uma ocorrência, mudança de dia sem duplicação e eventos atravessando meia-noite.
- Preservação de hora local ao atravessar horário de verão; exclusão de eventos.
- Metas conjuntas e individuais; atividades individuais não contam como conjuntas.
- Planejamento, sessões não concluídas e exclusões não geram progresso.
- Deduplicação, correção de duração, divisão na virada da semana, frequência e metas por prazo.
- Pausa, retomada, persistência e conclusão de cronômetro com UUID estável.
- Links de música permitidos e rejeição de hosts enganosos; duração e datas inválidas.

`python3 scripts/verify_project.py` confere referências do projeto, Info.plists, entitlements, esquema, assets e ícone sem transparência. Não verifica tipos Swift.

O workflow macOS compila o app e a extensão para simulador, sem assinatura. Não substitui os testes abaixo.

## Testes manuais no simulador

1. Entrar no modo demonstração, percorrer todas as abas e criar/editar/remover cada tipo de registro.
2. Criar um compromisso diário; mover uma ocorrência, cancelar outra e alterar esta e próximas. Conferir dias antigos e novos.
3. Iniciar cronômetro, aguardar, pausar, fechar/abrir app, retomar e concluir. Verificar duração e apenas um registro.
4. Registrar uma atividade conjunta e conferir uma meta individual de cada pessoa e uma conjunta. Corrigir/excluir e conferir recálculo.
5. Criar viagem, roteiro e despesas. Adicionar a mesma parada à agenda duas vezes: apenas um compromisso. Editar e excluir parada/viagem e conferir vínculos.
6. Compartilhar links musicais válidos e inválidos. Conferir autoria e abertura do serviço.
7. Testar modos claro, escuro, rosa e seguir sistema. Conferir Dynamic Type nos maiores tamanhos, VoiceOver, rotação e telas pequenas.
8. Instalar widgets pequeno e médio, testar links e estados vazios. Conferir saída do modo demonstração sem deixar dados antigos visíveis.
9. Ativar e negar notificações, editar horário/lembrete e excluir compromisso. Conferir a lista de solicitações no debugger e o disparo local.

## Testes em dois iPhones reais

Requer assinatura, CloudKit configurado e duas contas Apple diferentes no mesmo ambiente.

- Criar espaço apenas em A, convidar B, aceitar com o app fechado e aberto, e registrar o segundo perfil.
- Tentar convidar uma terceira conta e tentar usar o link com uma conta não convidada: recusar acesso.
- Criar, editar e excluir compromissos, metas, sessões, viagens e músicas em ambos os lados.
- Editar campos diferentes do mesmo item e, depois, o mesmo campo. Verificar a política de conciliação e ausência de crashes.
- Ativar modo avião em A, editar, restaurar conexão e verificar B. Repetir com A e B alterando offline.
- Aguardar importação de mudanças, abrir app e verificar agenda, metas, widgets e reagendamento de lembretes.
- Negar acesso/notificações, sair do iCloud e reentrar: verificar mensagens e preservação de dados locais sem erros fatais.
- Em dados descartáveis, testar saída do participante e encerramento pelo proprietário; conferir remoção de acesso e cache do widget.
- Em TestFlight, repetir convite e edição com schema publicado em Production. Não misturar builds Development e Production.

## Aceitação

A primeira versão é aceita quando os dois conseguem usar a agenda própria, compartilhar atividades, acompanhar metas, organizar viagens e abrir o app pelo widget; os testes automáticos passam, a compilação está verde e os cenários de dois aparelhos e acessibilidade foram revisados.

Registre resultados reais em `docs/STATUS.md`. Não marque sincronização ou revisão visual como aprovada apenas porque o código compilou.
