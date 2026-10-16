# Estado da entrega

## Implementação

Código inicial de todas as áreas do plano incluído: app SwiftUI, domínio testável, persistência local/CloudKit, convite privado para segunda conta, widget, temas, lembretes e documentação.

## Validações

| Verificação | Estado |
| --- | --- |
| Integridade de referências do projeto, plists, entitlements, assets e esquema | Verificada por `scripts/verify_project.py` no Windows |
| Testes de domínio Swift | Preparados; consultar resultado do GitHub Actions |
| Compilação app + widget | Preparada no workflow macOS; consultar GitHub Actions |
| Revisão visual no simulador | Pendente de Mac/Xcode; a imagem do README é ilustrativa |
| Convite e sincronização em duas contas reais | Pendente de configuração Apple Developer e dois iPhones |
| Notificações e widget em dispositivo real | Pendente de assinatura e instalação |
| Envio ao TestFlight | Pendente de assinatura Apple Developer e configuração App Store Connect |

O ambiente de implementação é Windows e não possui Xcode nem compilador Swift. Resultados de compilação executados remotamente devem ser registrados nesta tabela após confirmação. Os testes físicos continuam necessários mesmo quando a CI passa.

## Limitações conhecidas

- A sincronização iCloud e a atualização do widget são eventuais, sem garantia de tempo real.
- O cronômetro ativo pertence ao aparelho onde foi iniciado; somente a sessão concluída é compartilhada. Dois cronômetros diferentes não são deduplicados por semelhança de conteúdo.
- Os lembretes cobrem uma janela móvel de 30 dias e até 60 solicitações por aparelho.
- A hora recorrente segue o fuso do aparelho; não há fuso por evento. Pausas que atravessam semanas são rateadas proporcionalmente.
- Convites pendentes ocupam a vaga do segundo participante. Não há troca de parceiro/mesclagem de espaços no app nesta versão.
- Não há exportação, recuperação de exclusões ou interface de histórico de conflitos. Encerrar um espaço pode remover seu conteúdo; preserve o que for necessário antes.
- Ainda não foi feita auditoria de acessibilidade ou validação de produção do CloudKit.
