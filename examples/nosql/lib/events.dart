import 'package:event_sourcing/event_sourcing.dart';

class CreateDocumentEvent extends AutoIncrementEvent {
  final String collectionId;

  final Map<String, dynamic> patch;

  CreateDocumentEvent(this.collectionId, [this.patch = const {}])
    : super('CREATE_DOCUMENT', {'collectionId': collectionId, 'patch': patch});
}

class PatchDocumentEvent extends AutoIncrementEvent {
  final String collectionId;
  final String documentId;
  final Map<String, dynamic> patch;

  PatchDocumentEvent(
    this.collectionId,
    this.documentId, [
    this.patch = const {},
  ]) : super('PATCH_DOCUMENT', {
         'collectionId': collectionId,
         'documentId': documentId,
         'patch': patch,
       });
}

class SetDocumentEvent extends AutoIncrementEvent {
  final String collectionId;
  final String documentId;
  final Map<String, dynamic> patch;

  SetDocumentEvent(this.collectionId, this.documentId, [this.patch = const {}])
    : super('SET_DOCUMENT', {
        'collectionId': collectionId,
        'documentId': documentId,
        'patch': patch,
      });
}

class DuplicateDocumentEvent extends AutoIncrementEvent {
  final String collectionId;
  final String documentId;
  final String newDocumentId;

  DuplicateDocumentEvent(this.collectionId, this.documentId, this.newDocumentId)
    : super('DUPLICATE_DOCUMENT', {
        'collectionId': collectionId,
        'documentId': documentId,
        'newDocumentId': newDocumentId,
      });
}

class DeleteDocumentEvent extends AutoIncrementEvent {
  final String collectionId;
  final String documentId;

  DeleteDocumentEvent(this.collectionId, this.documentId)
    : super('DELETE_DOCUMENT', {
        'collectionId': collectionId,
        'documentId': documentId,
      });
}

class CreateCollectionEvent extends AutoIncrementEvent {
  final String collectionId;
  final String collectionName;

  CreateCollectionEvent(this.collectionId, this.collectionName)
    : super('CREATE_COLLECTION', {
        'collectionId': collectionId,
        'collectionName': collectionName,
      });
}

class UpdateCollectionEvent extends AutoIncrementEvent {
  final String collectionId;
  final String? collectionName;

  UpdateCollectionEvent(this.collectionId, [this.collectionName])
    : super('UPDATE_COLLECTION', {
        'collectionId': collectionId,
        'collectionName': collectionName,
      });
}

class DeleteCollectionEvent extends AutoIncrementEvent {
  final String collectionId;

  DeleteCollectionEvent(this.collectionId)
    : super('DELETE_COLLECTION', {'collectionId': collectionId});
}
