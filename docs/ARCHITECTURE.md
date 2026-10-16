# Arquitetura

## Organização

- `Core/`: domínio Foundation puro, expansão de recorrências, cálculo de metas, cronômetro codificável e contratos do widget. O pacote Swift permite testar essas regras sem simulador.
- `App/`: SwiftUI, Core Data/CloudKit, estado da aplicação e notificações locais.
- `Widget/`: extensão WidgetKit, com leitura do resumo no App Group.
- `Config/`: identificadores compartilhados, entitlements e Info.plists.

O projeto Xcode inclui os arquivos Core diretamente nos targets necessários; o aplicativo não precisa resolver dependências Swift Package. A extensão compila somente o contrato `WidgetSnapshot`, sem acessar o banco de dados.

## Persistência e sincronização

O modelo Core Data é construído programaticamente. `Space` é a raiz compartilhada. `Entry` representa registros tipados pelo campo `kind`: membros, eventos, exceções, metas, sessões, matérias, treinos, viagens, paradas, checklist, despesas e músicas. Todos possuem UUID estável.

Campos são atributos separados, com relações inversas `Space.entries`/`Entry.space`. Campos opcionais, padrões e ausência de constraints exclusivas mantêm compatibilidade com CloudKit. Os vínculos de domínio entre entradas usam UUIDs e permanecem no mesmo grafo de espaço compartilhado. Não há blobs JSON opacos para o conteúdo editável.

Dois stores SQLite espelhados por `NSPersistentCloudKitContainer`: privado para o proprietário e compartilhado para o convidado. Demonstração usa um terceiro store SQLite sem CloudKit. O timer e as preferências ficam em UserDefaults; o timer é separado por modo e UUID do espaço.

O contexto principal importa mudanças automaticamente e aplica `NSMergeByPropertyObjectTrumpMergePolicy`: edições locais em campos alterados prevalecem em conflitos desse contexto; os demais campos podem incorporar mudanças externas. Os formulários comparam com seu estado inicial para não regravar campos não editados. Não há histórico colaborativo nem garantia de edição simultânea sem perda no mesmo campo. Exclusões são tombstones (`deleted` no domínio, `removed` no Core Data para evitar colisão com `isDeleted`) para manter referências e propagar a remoção; a interface não oferece lixeira.

A criação do convite usa `CKShare` privado, busca a segunda conta pelo e-mail, define `.readWrite`, salva o share no CloudKit e informa o Core Data com `persistUpdatedShare`. Convites pendentes ocupam a segunda vaga. O link é enviado pela pessoa por meio da folha de compartilhamento do sistema. A aceitação é capturada pelos delegates do app/scene.

## Recorrência e horas

Eventos armazenam início, término, regra diária/semanal e término exclusivo opcional. A expansão usa calendário gregoriano e fuso do aparelho, preservando a hora local nas mudanças de horário de verão. A exibição em outro fuso segue esse aparelho; não há fuso fixo selecionável por evento nesta versão.

Exceções identificam evento-pai e início original. Podem substituir uma ocorrência ou cancelá-la. Alterar "esta e próximas" encerra a série anterior e cria uma nova. Uma ocorrência movida pode entrar em outra janela diária sem duplicação.

Metas semanais somam apenas sessões concluídas, da categoria e participantes correspondentes. UUIDs de sessão são deduplicados no cálculo. Sessões conjuntas não multiplicam pelo número de participantes. Metas do casal sem seleção exigem pelo menos dois participantes. Sessões são divididas proporcionalmente no limite de semana; não são mantidos intervalos individuais de pausa.

O cronômetro calcula duração por timestamps, sem depender de executar código continuamente em background. Pausar salva o tempo acumulado. Concluir grava uma sessão com o mesmo UUID do cronômetro e só então limpa o estado local.

## Integrações locais

Roteiro mantém `linkedID` do compromisso e deriva um identificador estável da parada: adicionar novamente atualiza o mesmo registro, inclusive em tentativas nos dois aparelhos. Editar a parada atualiza o compromisso vinculado. Editar o compromisso diretamente não modifica a parada; a parada é a origem da próxima atualização. Excluir o compromisso limpa o vínculo para permitir adicioná-lo novamente.

O app escreve atomicamente `snapshot.json` no App Group e pede recarga ao WidgetKit. A extensão monta timelines que retiram compromissos passados e zeram o progresso quando a semana termina. O sistema controla o momento real das atualizações.

Lembretes são locais, opt-in por aparelho, com até 60 solicitações nos próximos 30 dias. São recalculados ao editar, importar ou reabrir o app. Sem pushes próprios de conteúdo do casal ou servidor externo.

## Privacidade e evolução

Sem analytics, anúncios, login próprio, HealthKit, localização ou acesso ao calendário do sistema. iCloud processa os dados compartilhados; serviços musicais são acessados apenas ao abrir os links. O conteúdo pode ser lido e editado pelos dois participantes e por quem usa seus aparelhos desbloqueados.

Antes de alterar o modelo em versões futuras, definir e testar migração Core Data e compatibilidade do schema CloudKit. Não renomear/apagar tipos em produção sem estratégia de migração. Mudanças no contrato JSON do widget precisam preservar decodificação ou invalidar o snapshot.
