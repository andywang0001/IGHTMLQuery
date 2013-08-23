//
//  IGXMLNode.m
//  IGHTMLQuery
//
//  Created by Francis Chong on 20/8/13.
//  Copyright (c) 2013 Ignition Soft. All rights reserved.
//

#import "IGXMLNode.h"
#import "IGXMLDocument.h"
#import "IGHTMLDocument.h"

NSString* const IGXMLQueryErrorDomain = @"IGHTMLQueryError";

/**
 * extracted from Nokigiri
 * @see https://github.com/sparklemotion/nokogiri/blob/master/ext/nokogiri/xml_document.c
 */
static void recursively_remove_namespaces_from_node(xmlNodePtr node)
{
    xmlNodePtr child ;
    xmlAttrPtr property ;
    xmlSetNs(node, NULL);
    
    for (child = node->children ; child ; child = child->next)
        recursively_remove_namespaces_from_node(child);
    
    if (((node->type == XML_ELEMENT_NODE) ||
         (node->type == XML_XINCLUDE_START) ||
         (node->type == XML_XINCLUDE_END)) &&
        node->nsDef) {
        xmlFreeNsList(node->nsDef);
        node->nsDef = NULL;
    }
    
    if (node->type == XML_ELEMENT_NODE && node->properties != NULL) {
        property = node->properties ;
        while (property != NULL) {
            if (property->ns) property->ns = NULL ;
            property = property->next ;
        }
    }
}

@interface IGXMLNode ()
@property (nonatomic, assign) BOOL shouldFreeNode;
@end

@implementation IGXMLNode

- (id)initWithXMLNode:(xmlNodePtr)node {
    if ((self = [super init])) {
        _node = node;
        _shouldFreeNode = NO;
    }
    return self;
}

+ (id)nodeWithXMLNode:(xmlNodePtr)node {
    return [[self alloc] initWithXMLNode:node];
}

-(void) dealloc {
    if (_shouldFreeNode) {
        xmlFreeNode(_node);
    }
    _node = nil;
}

#pragma mark -

- (NSString *)tag {
    if (_node && _node->name) {
        return [NSString stringWithUTF8String:(const char *)_node->name];
    } else {
        return nil;
    }
}

- (void)setTag:(NSString*)tag {
    xmlNodeSetName(_node, (xmlChar*) [tag cStringUsingEncoding:NSUTF8StringEncoding]);
}

- (NSString *)text {
    xmlChar *key = xmlNodeGetContent(_node);
    NSString *text = (key ? [NSString stringWithUTF8String:(const char *)key] : @"");
    xmlFree(key);
    return text;
}

- (NSString *)xml {
    xmlBufferPtr buffer = xmlBufferCreate();
    xmlNodeDump(buffer, self.node->doc, self.node, 0, false);
    NSString *text = [NSString stringWithUTF8String:(const char *)xmlBufferContent(buffer)];
    xmlBufferFree(buffer);
    return text;
}

- (NSString *)innerXml {
    NSMutableString* innerXml = [NSMutableString string];
    xmlNodePtr cur = self.node->children;
    
    while (cur != nil) {
        if (cur->type == XML_TEXT_NODE) {
            xmlChar *key = xmlNodeGetContent(cur);
            NSString *text = (key ? [NSString stringWithUTF8String:(const char *)key] : @"");
            xmlFree(key);
            [innerXml appendString:text];
        } else {
            xmlBufferPtr buffer = xmlBufferCreate();
            xmlNodeDump(buffer, self.node->doc, cur, 0, false);
            NSString *text = [NSString stringWithUTF8String:(const char *)xmlBufferContent(buffer)];
            xmlBufferFree(buffer);
            [innerXml appendString:text];
        }
        cur = cur->next;
    }
    return innerXml;
}

- (NSError*) lastError {
    xmlErrorPtr error = xmlGetLastError();
    if (error) {
        NSDictionary* userInfo = @{
                                   @"domain": [NSString stringWithFormat:@"%i", error->domain],
                                   @"code": [NSString stringWithFormat:@"%i", error->code],
                                   @"message": error->message ? [NSString stringWithCString:error->message encoding:NSUTF8StringEncoding] : @"",
                                   @"file": error->file ? [NSString stringWithCString:error->file encoding:NSUTF8StringEncoding] : @"",
                                   @"line": [NSString stringWithFormat:@"%i", error->line],
                                   @"column": [NSString stringWithFormat:@"%i", error->int2]
                                   };
        return [NSError errorWithDomain:IGXMLQueryErrorDomain code:error->code userInfo:userInfo];
    } else {
        return nil;
    }
}

- (void)removeNamespaces {
    recursively_remove_namespaces_from_node(self.node);
}

-(id)copyWithZone:(NSZone *)zone{
    return [IGXMLNode nodeWithXMLNode:self.node];
}

#pragma mark - Traversal

- (IGXMLNode *) parent {
    xmlNodePtr parent = self.node->parent;
    if (!parent) {
        return nil;
    } else {
        return [IGXMLNode nodeWithXMLNode:parent];
    }
}

- (IGXMLNode *) nextSibling {
    xmlNodePtr sibling = xmlNextElementSibling(self.node);
    if (!sibling) {
        return nil;
    } else {
        return [IGXMLNode nodeWithXMLNode:sibling];
    }
}

- (IGXMLNode *) previousSibling {
    xmlNodePtr sibling = xmlPreviousElementSibling(self.node);
    if (!sibling) {
        return nil;
    } else {
        return [IGXMLNode nodeWithXMLNode:sibling];
    }
}

- (IGXMLNodeSet *)children {
    NSMutableArray* children = [NSMutableArray array];
    xmlNodePtr cur = _node->children;
    
    while (cur != nil) {
        if (cur->type == XML_ELEMENT_NODE) {
            [children addObject:[IGXMLNode nodeWithXMLNode:cur]];
        }
        cur = cur->next;
    }
    
    return [[IGXMLNodeSet alloc] initWithNodes:children];
}

-(IGXMLNode*) firstChild {
    xmlNodePtr cur = xmlFirstElementChild(self.node);

    if (cur != nil) {
        return [IGXMLNode nodeWithXMLNode:cur];
    }
    
    return nil;
}

- (NSString*) uniqueKey {
    return [NSString stringWithFormat:@"%x", (int) self.node];
}

- (BOOL) isEqual:(id)object {
    if (self == object) {
        return YES;
    }
    
    if (![object isKindOfClass:[self class]]) {
        return NO;
    }
    
    IGXMLNode* another = object;
    if (self.node == another.node) {
        return YES;
    }
    
    return NO;
}

- (NSUInteger)hash {
    return (NSUInteger) self.node;
}

#pragma mark - IGXMLNodeManipulation

-(instancetype) appendWithNode:(IGXMLNode*)child {
    if (!child) {
        @throw [NSException exceptionWithName:@"IGXMLNode Error"
                                       reason:@"child node cannot be nil"
                                     userInfo:nil];
    }
    
    xmlNodePtr newNode = xmlDocCopyNode(child.node, self.node->doc, 1);
    xmlAddChild(self.node, newNode);
    return [IGXMLNode nodeWithXMLNode:newNode];
}

-(instancetype) prependWithNode:(IGXMLNode*)child {
    if (!child) {
        @throw [NSException exceptionWithName:@"IGXMLNode Error"
                                       reason:@"child node cannot be nil"
                                     userInfo:nil];
    }
    
    xmlNodePtr cur = self.node;
    cur = cur->children;
    
    while (cur != nil && cur->type != XML_ELEMENT_NODE && cur->type != XML_TEXT_NODE) {
        cur = cur->next;
    }
    
    xmlNodePtr newNode = xmlDocCopyNode(child.node, self.node->doc, 1);
    if (cur) {
        xmlAddPrevSibling(cur, newNode);
    } else {
        xmlAddChild(self.node, newNode);
    }
    
    return [IGXMLNode nodeWithXMLNode:newNode];
}

-(IGXMLNode*) addChildWithNode:(IGXMLNode*)child {
    return [self appendWithNode:child];
}

-(IGXMLNode*) addNextSiblingWithNode:(IGXMLNode*)child {
    if (!child) {
        @throw [NSException exceptionWithName:@"IGXMLNode Error"
                                       reason:@"child node cannot be nil"
                                     userInfo:nil];
    }
    
    xmlNodePtr newNode = xmlDocCopyNode(child.node, self.node->doc, 1);
    xmlAddNextSibling(self.node, newNode);
    return [IGXMLNode nodeWithXMLNode:newNode];
}

-(IGXMLNode*) addPreviousSiblingWithNode:(IGXMLNode*)child {
    if (!child) {
        @throw [NSException exceptionWithName:@"IGXMLNode Error"
                                       reason:@"child node cannot be nil"
                                     userInfo:nil];
    }
    
    xmlNodePtr newNode = xmlDocCopyNode(child.node, self.node->doc, 1);
    xmlAddPrevSibling(self.node, newNode);
    return [IGXMLNode nodeWithXMLNode:newNode];
}

-(void) empty {
    xmlNodePtr cur = self.node;
    cur = cur->children;
    
    while (cur != nil) {
        xmlNodePtr next = cur->next;
        xmlUnlinkNode(cur);
        xmlFreeNode(cur);
        cur = next;
    }
}

-(void)remove {
    if (self.node->type == XML_NAMESPACE_DECL) {
        @throw [NSException exceptionWithName:IGXMLQueryErrorDomain reason:@"Cannot remove a namespace" userInfo:nil];
        return;
    }
    
    xmlUnlinkNode(self.node);
    _shouldFreeNode = YES;
}

#pragma mark - Manipulation - Shorthand

-(IGXMLNodeSet* (^)(NSString*)) append {
    return ^IGXMLNodeSet* (NSString* xml) {
        NSError* error = nil;
        IGXMLNode* node = [[IGXMLDocument alloc] initWithXMLString:xml
                                                             error:&error];
        if (node) {
            [self appendWithNode:node];
            return [[IGXMLNodeSet alloc] initWithNodes:@[node]];
        } else {
            // TODO: log error for diagnosis
            return [[IGXMLNodeSet alloc] initWithNodes:@[]];
        }
    };
}

-(IGXMLNodeSet* (^)(NSString*)) prepend {
    return ^IGXMLNodeSet* (NSString* xml) {
        NSError* error = nil;
        IGXMLNode* node = [[IGXMLDocument alloc] initWithXMLString:xml
                                                             error:&error];
        if (node) {
            [self prependWithNode:node];
            return [[IGXMLNodeSet alloc] initWithNodes:@[node]];
        } else {
            // TODO: log error for diagnosis
            return [[IGXMLNodeSet alloc] initWithNodes:@[]];
        }
    };
}

-(IGXMLNodeSet* (^)(NSString*))after {
    return ^IGXMLNodeSet* (NSString* xml) {
        NSError* error = nil;
        IGXMLNode* node = [[IGXMLDocument alloc] initWithXMLString:xml
                                                             error:&error];
        if (node) {
            [self addNextSiblingWithNode:node];
            return [[IGXMLNodeSet alloc] initWithNodes:@[node]];
        } else {
            // TODO: log error for diagnosis
            return [[IGXMLNodeSet alloc] initWithNodes:@[]];
        }
    };
}

-(IGXMLNodeSet* (^)(NSString*))before {
    return ^IGXMLNodeSet* (NSString* xml) {
        NSError* error = nil;
        IGXMLNode* node = [[IGXMLDocument alloc] initWithXMLString:xml
                                                             error:&error];
        if (node) {
            [self addPreviousSiblingWithNode:node];
            return [[IGXMLNodeSet alloc] initWithNodes:@[node]];
        } else {
            // TODO: log error for diagnosis
            return [[IGXMLNodeSet alloc] initWithNodes:@[]];
        }
    };
}

#pragma mark - Query

-(IGXMLNodeSet*) queryWithXPath:(NSString*)xpath {
    if (!xpath) {
        return [[IGXMLNodeSet alloc] initWithNodes:@[]];
    }
    
    if (!_node || !_node->doc) {
        return [[IGXMLNodeSet alloc] initWithNodes:@[]];
    }
    
    xmlXPathContextPtr context = xmlXPathNewContext(self.node->doc);
    if (context == NULL) {
		return [[IGXMLNodeSet alloc] initWithNodes:@[]];
    }
    
    context->node = self.node;
    
    xmlXPathObjectPtr object = xmlXPathEvalExpression((xmlChar *)[xpath UTF8String], context);
    if (object == NULL) {
		return [[IGXMLNodeSet alloc] initWithNodes:@[]];
    }
    
	xmlNodeSetPtr nodes = object->nodesetval;
    NSMutableArray *resultNodes = [NSMutableArray array];
	if (nodes != NULL) {
        for (NSInteger i = 0; i < nodes->nodeNr; i++) {
            [resultNodes addObject:[IGXMLNode nodeWithXMLNode:nodes->nodeTab[i]]];
        }
	}
    xmlXPathFreeObject(object);
    xmlXPathFreeContext(context);
    
    return [[IGXMLNodeSet alloc] initWithNodes:resultNodes];
}

-(IGXMLNodeSet* (^)(NSString*)) query {
    return ^IGXMLNodeSet* (NSString* query) {
        return [self queryWithXPath:query];
    };
}


#pragma mark - Attributes

- (NSString *)attribute:(NSString *)attName {
    return [self attribute:attName inNamespace:nil];
}

- (NSString *)attribute:(NSString *)attName inNamespace:(NSString *)ns {
    unsigned char *attCStr = ns ?
    xmlGetNsProp(self.node, (const xmlChar *)[attName cStringUsingEncoding:NSUTF8StringEncoding], (const xmlChar *)[ns cStringUsingEncoding:NSUTF8StringEncoding]) :
    xmlGetProp(self.node, (const xmlChar *)[attName cStringUsingEncoding:NSUTF8StringEncoding]) ;
    
    if (attCStr) {
        NSString* attibuteValue = [NSString stringWithUTF8String:(const char *)attCStr];
        xmlFree(attCStr);
        return attibuteValue;
    }
    
    return nil;
}

- (void) setAttribute:(NSString*)attName value:(NSString*)value {
    [self setAttribute:attName inNamespace:nil value:value];
}

- (void) setAttribute:(NSString*)attName inNamespace:(NSString*)ns value:(NSString*)value {
    if (!attName) {
        @throw [NSException exceptionWithName:@"IGXMLNode Error"
                                       reason:@"Attribute name cannot be nil"
                                     userInfo:nil];
    }
    
    if (!value) {
        @throw [NSException exceptionWithName:@"IGXMLNode Error"
                                       reason:@"Attribute value cannot be nil"
                                     userInfo:nil];
    }
    
    if (ns) {
        xmlNsPtr nsPtr = xmlSearchNs(self.node->doc, self.node, (const xmlChar *)[ns cStringUsingEncoding:NSUTF8StringEncoding]);
        xmlSetNsProp(self.node,
                     nsPtr,
                     (const xmlChar *)[attName cStringUsingEncoding:NSUTF8StringEncoding],
                     (const xmlChar *)[value cStringUsingEncoding:NSUTF8StringEncoding]);
    } else {
        xmlSetProp(self.node,
                   (const xmlChar *)[attName cStringUsingEncoding:NSUTF8StringEncoding],
                   (const xmlChar *)[value cStringUsingEncoding:NSUTF8StringEncoding]);
    }
}

- (void) removeAttribute:(NSString*)attName {
    [self removeAttribute:attName inNamespace:nil];
}

- (void) removeAttribute:(NSString*)attName inNamespace:(NSString*)ns {
    if (!attName) {
        @throw [NSException exceptionWithName:@"IGXMLNode Error"
                                       reason:@"Attribute name cannot be nil"
                                     userInfo:nil];
    }
    
    xmlAttrPtr attr = NULL;
    if (ns) {
        attr = xmlHasNsProp(self.node,
                            (const xmlChar *)[attName cStringUsingEncoding:NSUTF8StringEncoding],
                            (const xmlChar *)[ns cStringUsingEncoding:NSUTF8StringEncoding]);
    } else {
        attr = xmlHasProp(self.node, (const xmlChar *)[attName cStringUsingEncoding:NSUTF8StringEncoding]);
    }
    
    if (attr != NULL) {
        xmlRemoveProp(attr);
    }
}

- (NSArray *)attributeNames {
    NSMutableArray *names = [[NSMutableArray alloc] init];
    
    for(xmlAttrPtr attr = self.node->properties; attr != nil; attr = attr->next) {
        [names addObject:[[NSString alloc] initWithCString:(const char *)attr->name encoding:NSUTF8StringEncoding]];
    }
    
    return names;
}

- (id)objectForKeyedSubscript:(id)key {
    return [self attribute:key];
}

- (void)setObject:(id)obj forKeyedSubscript:(id <NSCopying>)key {
    [self setAttribute:(NSString*)key value:obj];
}

@end
